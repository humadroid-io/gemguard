# frozen_string_literal: true

require "csv"

class BaselineService
  BASELINE_URL = ENV.fetch("GEMGUARD_BASELINE_URL", "https://gemguard.example.com/baseline.csv.gz")

  class ImportError < StandardError; end

  class << self
    def import_from_url(url = BASELINE_URL)
      Rails.logger.info "Downloading baseline from #{url}..."

      response = fetch_baseline(url)
      import_from_gzipped_csv(response.body)
    end

    def import_from_file(path)
      Rails.logger.info "Importing baseline from #{path}..."

      data = File.binread(path)
      import_from_gzipped_csv(data)
    end

    def import_from_gzipped_csv(gzipped_data)
      csv_data = Zlib::GzipReader.new(StringIO.new(gzipped_data)).read
      import_from_csv(csv_data)
    end

    def import_from_csv(csv_data)
      count = 0
      batch = []
      batch_size = 1000

      CSV.parse(csv_data, headers: true) do |row|
        batch << {
          name: row["name"],
          version: row["version"],
          platform: row["platform"] || "ruby"
        }

        if batch.size >= batch_size
          import_batch(batch)
          count += batch.size
          batch.clear
          Rails.logger.info "Imported #{count} gems..." if (count % 10_000).zero?
        end
      end

      # Import remaining
      if batch.any?
        import_batch(batch)
        count += batch.size
      end

      Rails.logger.info "Baseline import complete: #{count} gems imported"
      count
    end

    def baseline_imported?
      Setting.get(:baseline_imported_at).present?
    end

    def mark_baseline_imported!
      Setting.set(:baseline_imported_at, Time.current.iso8601)
    end

    def generate_baseline(output_path)
      Rails.logger.info "Generating baseline file..."

      specs = fetch_all_specs_from_rubygems
      write_baseline_csv(specs, output_path)

      Rails.logger.info "Baseline generated: #{specs.size} gems written to #{output_path}"
      specs.size
    end

    private

    def fetch_baseline(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 30
      http.read_timeout = 300 # 5 minutes for large files

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise ImportError, "Failed to download baseline: #{response.code} #{response.message}"
      end

      response
    end

    def import_batch(batch)
      # Group by gem name for efficient package lookup/creation
      batch.group_by { |g| g[:name] }.each do |name, versions|
        gem_package = GemPackage.find_or_create_by!(name: name)

        versions.each do |v|
          gem_package.versions.find_or_create_by!(
            version: v[:version],
            platform: v[:platform]
          ) do |gv|
            gv.status = :approved
            gv.first_seen_at = Time.current
          end
        end
      end
    end

    def fetch_all_specs_from_rubygems
      specs = []

      # Fetch all three spec types
      %i[all latest prerelease].each do |type|
        raw = RubygemsClient.fetch_specs(type)
        next unless raw

        parsed = RubygemsClient.parse_specs(raw)
        specs.concat(parsed)
      end

      # Deduplicate
      specs.uniq { |name, version, platform| [name, version.to_s, platform.to_s] }
    end

    def write_baseline_csv(specs, output_path)
      Zlib::GzipWriter.open(output_path) do |gz|
        gz.write("name,version,platform\n")

        specs.each do |name, version, platform|
          platform_str = platform.to_s.presence || "ruby"
          gz.write("#{escape_csv(name)},#{escape_csv(version.to_s)},#{escape_csv(platform_str)}\n")
        end
      end
    end

    def escape_csv(value)
      if value.include?(",") || value.include?('"') || value.include?("\n")
        "\"#{value.gsub('"', '""')}\""
      else
        value
      end
    end
  end
end
