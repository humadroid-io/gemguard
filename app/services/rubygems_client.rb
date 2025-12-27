class RubygemsClient
  include HTTParty

  base_uri "https://rubygems.org"

  class << self
    def fetch_specs(type = :all)
      filename = case type
      when :latest then "latest_specs.4.8.gz"
      when :prerelease then "prerelease_specs.4.8.gz"
      else "specs.4.8.gz"
      end

      response = get("/#{filename}", timeout: 60)
      return nil unless response.success?

      response.body
    end

    def fetch_gem_info(gem_name)
      response = get("/api/v1/gems/#{gem_name}.json", timeout: 10)
      return nil unless response.success?

      JSON.parse(response.body)
    end

    def fetch_version_info(gem_name, version)
      response = get("/api/v1/versions/#{gem_name}.json", timeout: 10)
      return nil unless response.success?

      versions = JSON.parse(response.body)
      versions.find { |v| v["number"] == version }
    rescue JSON::ParserError
      nil
    end

    def download_file(url, local_path)
      FileUtils.mkdir_p(File.dirname(local_path))

      response = HTTParty.get(url, timeout: 120, stream_body: true) do |fragment|
        File.open(local_path, "ab") { |file| file.write(fragment) }
      end

      unless response.success?
        File.delete(local_path) if File.exist?(local_path)
        return false
      end

      true
    rescue => e
      Rails.logger.error("Failed to download #{url}: #{e.message}")
      File.delete(local_path) if File.exist?(local_path)
      false
    end

    def parse_specs(gzipped_data)
      return [] unless gzipped_data

      io = StringIO.new(gzipped_data)
      gz = Zlib::GzipReader.new(io)
      Marshal.load(gz.read)
    rescue
      Rails.logger.error("Failed to parse specs:")
      []
    end
  end
end
