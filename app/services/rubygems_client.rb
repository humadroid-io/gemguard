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
      versions = fetch_all_versions(gem_name)
      return nil unless versions

      versions.find { |v| v["number"] == version }
    end

    def fetch_all_versions(gem_name)
      response = get("/api/v1/versions/#{gem_name}.json", timeout: 10)
      return nil unless response.success?

      JSON.parse(response.body)
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

    def fetch_dependencies(gems)
      response = get(
        "/api/v1/dependencies",
        query: {gems: Array(gems).join(",")},
        timeout: 30
      )
      return nil unless response.success?

      response.body
    end

    # Parses RubyGems specs from gzipped Marshal data.
    #
    # Security note: Marshal.load is required here because RubyGems uses Marshal
    # format for specs files (specs.4.8.gz). This is the standard protocol and
    # cannot be avoided. The security risk is mitigated because:
    #   1. Data is fetched only from rubygems.org (trusted source)
    #   2. HTTPS ensures data integrity in transit
    #   3. Specs contain only simple data: [name, Gem::Version, platform] tuples
    #
    # rubocop:disable Security/MarshalLoad
    def parse_specs(gzipped_data)
      return [] unless gzipped_data

      io = StringIO.new(gzipped_data)
      gz = Zlib::GzipReader.new(io)
      Marshal.load(gz.read)
    rescue => e
      Rails.logger.error("Failed to parse specs: #{e.message}")
      []
    end
    # rubocop:enable Security/MarshalLoad

    # The dependency API returns a Marshal-serialized array of hashes.
    # rubocop:disable Security/MarshalLoad
    def parse_dependencies(payload)
      return [] unless payload

      Marshal.load(payload)
    rescue => e
      Rails.logger.error("Failed to parse dependencies: #{e.message}")
      []
    end
    # rubocop:enable Security/MarshalLoad
  end
end
