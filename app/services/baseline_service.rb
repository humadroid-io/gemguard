# frozen_string_literal: true

require "csv"

# Utility service for baseline management.
#
# With the new design, the baseline is simply the specs files stored in
# storage/specs/raw/. All versions in those files are considered "known"
# and approved. Only NEW versions (detected by SyncSpecsJob after baseline)
# will be quarantined.
#
# This service provides:
# - Status checking (baseline_imported?)
# - Export functionality (generate_baseline for debugging/backup)
#
# DEPRECATED: CSV/dump import methods have been removed. Use
# SpecsBaselineImporter.import instead, which only saves specs files
# without populating the database.
class BaselineService
  class << self
    def baseline_imported?
      Setting.get(:baseline_imported_at).present?
    end

    def baseline_imported_at
      Setting.get(:baseline_imported_at)
    end

    def baseline_source
      Setting.get(:baseline_source)
    end

    # Generate a CSV export of current specs (for backup/debugging)
    def generate_baseline(output_path)
      Rails.logger.info "Generating baseline export..."

      specs = fetch_all_specs_from_rubygems

      write_baseline_csv(specs, output_path)

      Rails.logger.info "Baseline generated: #{specs.size} gems written to #{output_path}"
      specs.size
    end

    # Generate a CSV export from local specs files (no network required)
    def generate_baseline_from_local(output_path)
      Rails.logger.info "Generating baseline export from local specs..."

      specs = load_local_specs

      write_baseline_csv(specs, output_path)

      Rails.logger.info "Baseline generated: #{specs.size} gems written to #{output_path}"
      specs.size
    end

    private

    def fetch_all_specs_from_rubygems
      specs = []

      %i[all latest prerelease].each do |type|
        raw = RubygemsClient.fetch_specs(type)
        next unless raw

        parsed = RubygemsClient.parse_specs(raw)
        specs.concat(parsed)
      end

      deduplicate_specs(specs)
    end

    def raw_specs_path
      Rails.root.join("storage", "specs", "raw")
    end

    def load_local_specs
      specs = []

      %w[specs.4.8.gz latest_specs.4.8.gz prerelease_specs.4.8.gz].each do |filename|
        path = raw_specs_path.join(filename)
        next unless File.exist?(path)

        data = File.binread(path)
        parsed = RubygemsClient.parse_specs(data)
        specs.concat(parsed)
      end

      deduplicate_specs(specs)
    end

    def deduplicate_specs(specs)
      specs.uniq { |name, version, platform| [name, version.to_s, platform.to_s.presence || "ruby"] }
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
