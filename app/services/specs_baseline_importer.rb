# frozen_string_literal: true

# Imports baseline specs from RubyGems.org
#
# This establishes the baseline of "known" gem versions. All versions in the
# baseline are considered approved - only NEW versions (detected by SyncSpecsJob
# after baseline import) will be quarantined.
#
# IMPORTANT: This service only saves specs files to storage. It does NOT create
# any GemPackage or GemVersion records. Those are created on-demand when gems
# are actually requested by Bundler.
class SpecsBaselineImporter
  SPEC_TYPES = {
    all: "specs.4.8.gz",
    latest: "latest_specs.4.8.gz",
    prerelease: "prerelease_specs.4.8.gz"
  }.freeze

  class << self
    def import(include_prerelease: false)
      Rails.logger.info("SpecsBaselineImporter: Starting baseline import")

      # Download and save all spec types
      types_to_import = [:all, :latest]
      types_to_import << :prerelease if include_prerelease

      specs_counts = {}

      types_to_import.each do |type|
        count = download_and_save_specs(type)
        specs_counts[type] = count
      end

      # Also fetch prerelease for raw storage even if not "importing" it
      # (needed for SyncSpecsJob to diff against)
      unless include_prerelease
        download_and_save_specs(:prerelease, raw_only: true)
      end

      # Mark baseline as imported
      Setting.set(:baseline_imported_at, Time.current.iso8601)
      Setting.set(:baseline_source, "specs")

      total = specs_counts.values.sum
      Rails.logger.info("SpecsBaselineImporter: Completed baseline import")
      Rails.logger.info("  - specs.4.8.gz: #{specs_counts[:all] || 0} versions")
      Rails.logger.info("  - latest_specs.4.8.gz: #{specs_counts[:latest] || 0} versions")
      Rails.logger.info("  - prerelease_specs.4.8.gz: #{specs_counts[:prerelease] || 0} versions") if include_prerelease

      total
    end

    def baseline_imported?
      Setting.get(:baseline_imported_at).present?
    end

    private

    def download_and_save_specs(type, raw_only: false)
      Rails.logger.info("SpecsBaselineImporter: Fetching #{type} specs from RubyGems...")

      data = RubygemsClient.fetch_specs(type)
      unless data
        Rails.logger.error("SpecsBaselineImporter: Failed to fetch #{type} specs")
        return 0
      end

      # Parse to get count for logging
      specs = RubygemsClient.parse_specs(data)
      count = specs.size

      Rails.logger.info("SpecsBaselineImporter: Downloaded #{count} entries from #{type} specs")

      # Save raw specs (for SyncSpecsJob to diff against)
      save_specs_file(raw_specs_path, type, data)

      # Save filtered specs (for serving to Bundler)
      # During baseline import, all versions are approved so filtered = raw
      unless raw_only
        save_specs_file(filtered_specs_path, type, data)
      end

      count
    end

    def save_specs_file(base_path, type, data)
      filename = SPEC_TYPES[type]
      path = base_path.join(filename)

      FileUtils.mkdir_p(base_path)
      atomic_write(path, data)

      Rails.logger.info("SpecsBaselineImporter: Saved specs to #{path}")
    end

    def atomic_write(path, data)
      temp_path = "#{path}.tmp.#{Process.pid}"
      File.binwrite(temp_path, data)
      File.rename(temp_path, path)
    rescue => e
      File.delete(temp_path) if File.exist?(temp_path)
      raise e
    end

    def raw_specs_path
      Rails.root.join("storage", "specs", "raw")
    end

    def filtered_specs_path
      Rails.root.join("storage", "specs")
    end
  end
end
