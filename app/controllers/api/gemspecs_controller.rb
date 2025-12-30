module Api
  class GemspecsController < BaseController
    include GemVersionLookup

    def show
      gemspec_file = params[:id]
      return head :bad_request unless gemspec_file.end_with?(".gemspec.rz")

      parsed = parse_gem_identifier(gemspec_file, ".gemspec.rz")
      return head :bad_request unless parsed

      gem_version = find_or_fetch_gem_version(parsed)

      handle_gem_version_response(gem_version) do |gv|
        serve_gemspec(gv, gemspec_file)
      end
    end

    private

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
