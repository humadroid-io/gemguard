module Api
  class GemsController < BaseController
    def show
      gem_file = params[:id]
      return head :bad_request unless gem_file.end_with?(".gem")

      parsed = parse_gem_filename(gem_file)
      return head :bad_request unless parsed

      gem_version = find_or_fetch_gem_version(parsed)

      if gem_version.nil?
        head :not_found
      elsif gem_version.blocked?
        head :forbidden
      elsif !gem_version.available?
        head :not_found # Return 404 for quarantined gems (consistent with filtered specs)
      else
        serve_gem(gem_version, gem_file)
      end
    end

    private

    def parse_gem_filename(filename)
      name = filename.chomp(".gem")
      parts = name.split("-")

      return nil if parts.size < 2

      version_index = parts.rindex { |p| p.match?(/^\d/) }
      return nil unless version_index

      gem_name = parts[0...version_index].join("-")
      version = parts[version_index]
      platform = parts[(version_index + 1)..].join("-").presence || "ruby"

      { name: gem_name, version: version, platform: platform }
    end

    def find_or_fetch_gem_version(parsed)
      # First, try to find in database
      gem_version = find_gem_version(parsed)
      return gem_version if gem_version

      # Not in database - check upstream if gem exists
      fetch_gem_from_upstream(parsed)
    end

    def find_gem_version(parsed)
      gem_package = GemPackage.find_by(name: parsed[:name])
      return nil unless gem_package

      gem_package.versions.find_by(version: parsed[:version], platform: parsed[:platform])
    end

    def fetch_gem_from_upstream(parsed)
      # Check if gem exists on RubyGems
      gem_info = RubygemsClient.fetch_gem_info(parsed[:name])
      return nil unless gem_info

      # Check if the specific version exists
      version_info = RubygemsClient.fetch_version_info(parsed[:name], parsed[:version])
      return nil unless version_info

      # Create the gem package and version
      create_gem_version(parsed, gem_info, version_info)
    end

    def create_gem_version(parsed, gem_info, version_info)
      gem_package = GemPackage.find_or_create_by!(name: parsed[:name]) do |pkg|
        pkg.info = gem_info["info"]
        pkg.homepage_url = gem_info["homepage_uri"]
        pkg.downloads_count = gem_info["downloads"]
        pkg.tracked_at = Time.current # Mark as tracked when first downloaded
      end

      # Mark as tracked if existing package wasn't already
      gem_package.track!

      published_at = Time.parse(version_info["created_at"]) rescue Time.current

      # Check if actively quarantined (either in QuarantinedVersion table or recently published)
      is_quarantined = QuarantinedVersion.quarantined?(parsed[:name], parsed[:version], parsed[:platform]) ||
                       published_at > Setting.quarantine_period.ago

      gem_package.versions.create!(
        version: parsed[:version],
        platform: parsed[:platform],
        published_at: published_at,
        first_seen_at: Time.current,
        status: is_quarantined ? :quarantined : :approved
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Race condition - another request created it
      find_gem_version(parsed)
    end

    def serve_gem(gem_version, gem_file)
      local_path = gems_path.join(gem_file)

      # Mark the gem as tracked when it's actually downloaded
      gem_version.gem_package.track!

      unless File.exist?(local_path)
        success = download_gem(gem_version, local_path)
        unless success
          # Stream directly from upstream without caching
          stream_from_upstream(gem_version)
          return
        end
      end

      AuditLog.log_download(gem_name: gem_version.gem_name, version: gem_version.version, request: request)
      set_gem_headers(gem_version, local_path)
      send_file local_path, type: "application/octet-stream", disposition: "attachment"
    end

    def download_gem(gem_version, local_path)
      return false unless Setting.cache_gems?

      upstream = Setting.upstream_source
      url = "#{upstream}/gems/#{gem_version.gem_file_name}"

      success = RubygemsClient.download_file(url, local_path)

      if success && File.exist?(local_path)
        gem_version.update!(cached_at: Time.current, file_size: File.size(local_path))
      end

      success
    end

    def stream_from_upstream(gem_version)
      upstream = Setting.upstream_source
      url = "#{upstream}/gems/#{gem_version.gem_file_name}"

      response = HTTParty.get(url, timeout: 120)

      if response.success?
        # Write to temp file to avoid binary output to console
        temp_path = Rails.root.join("tmp", "gems", gem_version.gem_file_name)
        FileUtils.mkdir_p(File.dirname(temp_path))
        File.binwrite(temp_path, response.body)

        AuditLog.log_download(gem_name: gem_version.gem_name, version: gem_version.version, request: request)
        send_file temp_path, type: "application/octet-stream", disposition: "attachment"
      else
        head :bad_gateway
      end
    rescue StandardError => e
      Rails.logger.error("Failed to stream gem: #{e.message}")
      head :bad_gateway
    end

    def set_gem_headers(gem_version, path)
      response.headers["Content-Length"] = File.size(path).to_s
      response.headers["ETag"] = gem_version.checksum if gem_version.checksum.present?
    end
  end
end
