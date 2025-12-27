# frozen_string_literal: true

require "open-uri"
require "rubygems/package"

class RubygemsDumpImporter
  S3_BUCKET = "https://s3-us-west-2.amazonaws.com/rubygems-dumps/"
  DUMP_PREFIX = "production/public_postgresql"

  class ImportError < StandardError; end

  class << self
    def import
      Rails.logger.info "Starting RubyGems dump import..."

      dump_url = find_latest_dump_url
      Rails.logger.info "Found dump: #{dump_url}"

      Dir.mktmpdir do |tmpdir|
        tar_path = File.join(tmpdir, "dump.tar")
        sql_path = File.join(tmpdir, "PostgreSQL.sql")

        download_dump(dump_url, tar_path)
        extract_sql(tar_path, sql_path)
        import_sql(sql_path)
      end

      Setting.set(:baseline_imported_at, Time.current.iso8601)
      Setting.set(:baseline_source, "rubygems_dump")

      Rails.logger.info "RubyGems dump import complete"
    end

    def find_latest_dump_url
      # Query S3 bucket for latest dump
      list_url = "#{S3_BUCKET}?prefix=#{DUMP_PREFIX}"
      response = URI.open(list_url, read_timeout: 30).read

      # Parse XML response to find latest key
      keys = response.scan(/<Key>([^<]+)<\/Key>/).flatten
      latest_key = keys.select { |k| k.end_with?(".tar") }.max

      raise ImportError, "No dump files found in S3 bucket" unless latest_key

      "#{S3_BUCKET}#{latest_key}"
    end

    def download_dump(url, output_path)
      Rails.logger.info "Downloading dump (this may take a while)..."

      # Use streaming download for large file
      URI.open(url, read_timeout: 600) do |remote|
        File.open(output_path, "wb") do |local|
          while (chunk = remote.read(1024 * 1024))
            local.write(chunk)
          end
        end
      end

      Rails.logger.info "Download complete: #{File.size(output_path)} bytes"
    end

    def extract_sql(tar_path, output_path)
      Rails.logger.info "Extracting SQL from tar archive..."

      File.open(tar_path, "rb") do |file|
        Gem::Package::TarReader.new(file) do |tar|
          tar.each do |entry|
            if entry.full_name.include?("PostgreSQL.sql.gz")
              Rails.logger.info "Found: #{entry.full_name}"

              # Decompress gzip content
              gz = Zlib::GzipReader.new(StringIO.new(entry.read))
              File.write(output_path, gz.read)
              gz.close

              Rails.logger.info "Extracted SQL: #{File.size(output_path)} bytes"
              return
            end
          end
        end
      end

      raise ImportError, "PostgreSQL.sql.gz not found in archive"
    end

    def import_sql(sql_path)
      Rails.logger.info "Parsing PostgreSQL dump..."

      rubygems = {}
      versions_count = 0

      # Parse the SQL file for COPY statements
      File.open(sql_path, "r") do |file|
        current_table = nil
        columns = []

        file.each_line do |line|
          line = line.strip

          # Detect COPY statement start
          if line.start_with?("COPY public.rubygems ")
            current_table = :rubygems
            columns = parse_copy_columns(line)
            next
          elsif line.start_with?("COPY public.versions ")
            current_table = :versions
            columns = parse_copy_columns(line)
            next
          end

          # End of COPY block
          if line == "\\."
            current_table = nil
            columns = []
            next
          end

          # Process data rows
          next unless current_table

          values = line.split("\t")

          case current_table
          when :rubygems
            process_rubygem_row(columns, values, rubygems)
          when :versions
            versions_count += process_version_row(columns, values, rubygems)

            if (versions_count % 10_000).zero?
              Rails.logger.info "Imported #{versions_count} versions..."
            end
          end
        end
      end

      Rails.logger.info "Import complete: #{rubygems.size} gems, #{versions_count} versions"
      versions_count
    end

    private

    def parse_copy_columns(line)
      # COPY public.tablename (col1, col2, col3) FROM stdin;
      match = line.match(/\(([^)]+)\)/)
      return [] unless match

      match[1].split(",").map(&:strip)
    end

    def process_rubygem_row(columns, values, rubygems)
      data = columns.zip(values).to_h

      id = data["id"]
      name = data["name"]

      rubygems[id] = name if id && name
    end

    def process_version_row(columns, values, rubygems)
      data = columns.zip(values).to_h

      rubygem_id = data["rubygem_id"]
      version = data["number"]
      platform = data["platform"].presence || "ruby"
      created_at = parse_timestamp(data["created_at"])
      indexed = data["indexed"] != "f" # Default to true unless explicitly false

      return 0 unless rubygem_id && version && indexed

      gem_name = rubygems[rubygem_id]
      return 0 unless gem_name

      # Skip if platform is nil (corrupted data)
      platform = "ruby" if platform == "\\N"

      gem_package = GemPackage.find_or_create_by!(name: gem_name)
      gem_package.versions.find_or_create_by!(
        version: version,
        platform: platform
      ) do |gv|
        gv.status = :approved
        gv.first_seen_at = created_at || Time.current
      end

      1
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # Skip duplicates or invalid records
      0
    end

    def parse_timestamp(value)
      return nil if value.nil? || value == "\\N"

      Time.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
