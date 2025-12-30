module Api
  class GemsController < BaseController
    include GemVersionLookup

    def show
      gem_file = params[:id]
      return head :bad_request unless gem_file.end_with?(".gem")

      parsed = parse_gem_identifier(gem_file, ".gem")
      return head :bad_request unless parsed

      gem_version = find_or_fetch_gem_version(parsed)

      handle_gem_version_response(gem_version) do |gv|
        serve_gem(gv, gem_file)
      end
    end

    private

    # Hook: mark gem package as tracked when first created
    def configure_new_gem_package(pkg)
      pkg.tracked_at = Time.current
    end

    # Hook: ensure existing packages get tracked too
    def after_gem_package_found(gem_package)
      gem_package.track!
    end

    def serve_gem(gem_version, gem_file)
      local_path = gems_path.join(gem_file)

      # Mark the gem as tracked when it's actually downloaded
      gem_version.gem_package.track!

      unless File.exist?(local_path)
        success = download_gem(gem_version, local_path)
        unless success
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
        temp_path = Rails.root.join("tmp", "gems", gem_version.gem_file_name)
        FileUtils.mkdir_p(File.dirname(temp_path))
        File.binwrite(temp_path, response.body)

        AuditLog.log_download(gem_name: gem_version.gem_name, version: gem_version.version, request: request)
        send_file temp_path, type: "application/octet-stream", disposition: "attachment"
      else
        head :bad_gateway
      end
    rescue => e
      Rails.logger.error("Failed to stream gem: #{e.message}")
      head :bad_gateway
    end

    def set_gem_headers(gem_version, path)
      response.headers["Content-Length"] = File.size(path).to_s
      response.headers["ETag"] = gem_version.checksum if gem_version.checksum.present?
    end
  end
end
