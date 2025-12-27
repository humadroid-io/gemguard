# frozen_string_literal: true

class SpecsBaselineImporter
  BATCH_SIZE = 1000

  class << self
    def import(include_prerelease: false)
      Rails.logger.info("SpecsBaselineImporter: Starting import from specs files")

      total_count = 0

      # Import from main specs (all stable versions)
      total_count += import_specs(:all)

      # Optionally import prereleases
      if include_prerelease
        total_count += import_specs(:prerelease)
      end

      # Save raw specs for future use
      save_raw_specs

      Setting.set(:baseline_imported_at, Time.current.iso8601)
      Setting.set(:baseline_source, "specs")

      Rails.logger.info("SpecsBaselineImporter: Completed import of #{total_count} versions")
      total_count
    end

    private

    def import_specs(type)
      Rails.logger.info("SpecsBaselineImporter: Fetching #{type} specs from RubyGems...")

      data = RubygemsClient.fetch_specs(type)
      unless data
        Rails.logger.error("SpecsBaselineImporter: Failed to fetch #{type} specs")
        return 0
      end

      specs = RubygemsClient.parse_specs(data)
      Rails.logger.info("SpecsBaselineImporter: Parsed #{specs.size} entries from #{type} specs")

      import_specs_data(specs, data, type)
    end

    def import_specs_data(specs, raw_data, type)
      # Group specs by gem name for efficient batch processing
      grouped = specs.group_by { |name, _version, _platform| name }

      Rails.logger.info("SpecsBaselineImporter: Processing #{grouped.size} unique gems...")

      imported_count = 0
      gem_names = grouped.keys

      gem_names.each_slice(BATCH_SIZE) do |batch_names|
        # Find or create gem packages in batch
        existing_packages = GemPackage.where(name: batch_names).index_by(&:name)

        batch_names.each do |gem_name|
          gem_package = existing_packages[gem_name] || GemPackage.create!(name: gem_name)

          # Get existing versions for this package
          existing_versions = gem_package.versions.pluck(:version, :platform).to_set

          # Create missing versions
          versions_to_create = []
          grouped[gem_name].each do |_name, version, platform|
            version_str = version.to_s
            platform_str = platform.to_s.presence || "ruby"

            next if existing_versions.include?([version_str, platform_str])

            versions_to_create << {
              gem_package_id: gem_package.id,
              version: version_str,
              platform: platform_str,
              status: :approved,
              first_seen_at: Time.current
            }
          end

          if versions_to_create.any?
            GemVersion.insert_all(versions_to_create)
            imported_count += versions_to_create.size
          end
        end

        # Log progress
        processed = gem_names.index(batch_names.last).to_i + 1
        Rails.logger.info("SpecsBaselineImporter: Processed #{processed}/#{gem_names.size} gems (#{imported_count} versions)")
      end

      # Save raw specs
      save_raw_spec_file(type, raw_data)

      imported_count
    end

    def save_raw_specs
      # This ensures we have the raw specs for filtering
      %i[all latest prerelease].each do |type|
        next if raw_spec_exists?(type)

        data = RubygemsClient.fetch_specs(type)
        save_raw_spec_file(type, data) if data
      end
    end

    def save_raw_spec_file(type, data)
      return unless data

      filename = case type
      when :latest then "latest_specs.4.8.gz"
      when :prerelease then "prerelease_specs.4.8.gz"
      else "specs.4.8.gz"
      end

      path = raw_specs_path.join(filename)
      FileUtils.mkdir_p(raw_specs_path)
      File.binwrite(path, data)
      Rails.logger.info("SpecsBaselineImporter: Saved raw specs to #{path}")
    end

    def raw_spec_exists?(type)
      filename = case type
      when :latest then "latest_specs.4.8.gz"
      when :prerelease then "prerelease_specs.4.8.gz"
      else "specs.4.8.gz"
      end

      File.exist?(raw_specs_path.join(filename))
    end

    def raw_specs_path
      Rails.root.join("storage", "specs", "raw")
    end
  end
end
