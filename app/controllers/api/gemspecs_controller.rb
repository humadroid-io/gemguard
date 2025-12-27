module Api
  class GemspecsController < BaseController
    def show
      gemspec_file = params[:id]
      return head :bad_request unless gemspec_file.end_with?(".gemspec.rz")

      parsed = parse_gemspec_filename(gemspec_file)
      return head :bad_request unless parsed

      gem_version = find_or_fetch_gem_version(parsed)

      if gem_version.nil?
        head :not_found
      elsif gem_version.blocked?
        head :forbidden
      elsif !gem_version.available?
        head :not_found # Return 404 for quarantined gems (consistent with filtered specs)
      else
        serve_gemspec(gem_version, gemspec_file)
      end
    end

    private

    def parse_gemspec_filename(filename)
      name = filename.chomp(".gemspec.rz")
      parts = name.split("-")

      return nil if parts.size < 2

      version_index = parts.rindex { |p| p.match?(/^\d/) }
      return nil unless version_index

      gem_name = parts[0...version_index].join("-")
      version = parts[version_index]
      platform = parts[(version_index + 1)..].join("-").presence || "ruby"

      {name: gem_name, version: version, platform: platform}
    end

    def find_or_fetch_gem_version(parsed)
      gem_version = find_gem_version(parsed)
      return gem_version if gem_version

      fetch_gem_from_upstream(parsed)
    end

    def find_gem_version(parsed)
      gem_package = GemPackage.find_by(name: parsed[:name])
      return nil unless gem_package

      gem_package.versions.find_by(version: parsed[:version], platform: parsed[:platform])
    end

    def fetch_gem_from_upstream(parsed)
      gem_info = RubygemsClient.fetch_gem_info(parsed[:name])
      return nil unless gem_info

      version_info = RubygemsClient.fetch_version_info(parsed[:name], parsed[:version])
      return nil unless version_info

      create_gem_version(parsed, gem_info, version_info)
    end

    def create_gem_version(parsed, gem_info, version_info)
      gem_package = GemPackage.find_or_create_by!(name: parsed[:name]) do |pkg|
        pkg.info = gem_info["info"]
        pkg.homepage_url = gem_info["homepage_uri"]
        pkg.downloads_count = gem_info["downloads"]
      end

      published_at = begin
        Time.parse(version_info["created_at"])
      rescue
        Time.current
      end

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
      find_gem_version(parsed)
    end

    def serve_gemspec(gem_version, gemspec_file)
      local_path = specs_path.join("quick", gemspec_file)

      unless File.exist?(local_path)
        success = download_gemspec(gem_version, local_path)
        unless success
          stream_from_upstream(gem_version)
          return
        end
      end

      send_file local_path, type: "application/x-deflate", disposition: "inline"
    end

    def download_gemspec(gem_version, local_path)
      return false unless Setting.cache_gems?

      FileUtils.mkdir_p(File.dirname(local_path))

      upstream = Setting.upstream_source
      url = "#{upstream}/quick/Marshal.4.8/#{gem_version.gemspec_file_name}"

      RubygemsClient.download_file(url, local_path)
    end

    def stream_from_upstream(gem_version)
      upstream = Setting.upstream_source
      url = "#{upstream}/quick/Marshal.4.8/#{gem_version.gemspec_file_name}"

      response = HTTParty.get(url, timeout: 30)

      if response.success?
        # Write to temp file to avoid binary output to console
        temp_path = Rails.root.join("tmp", "gemspecs", gem_version.gemspec_file_name)
        FileUtils.mkdir_p(File.dirname(temp_path))
        File.binwrite(temp_path, response.body)

        send_file temp_path, type: "application/x-deflate", disposition: "inline"
      else
        head :bad_gateway
      end
    rescue => e
      Rails.logger.error("Failed to stream gemspec: #{e.message}")
      head :bad_gateway
    end
  end
end
