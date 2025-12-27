# frozen_string_literal: true

class SpecsAvailabilityService
  SPEC_FILES = %w[specs.4.8.gz latest_specs.4.8.gz prerelease_specs.4.8.gz].freeze

  class << self
    def available?
      # Check if at least one raw spec file exists
      # Raw specs are needed to regenerate filtered specs
      SPEC_FILES.any? { |file| File.exist?(raw_specs_path.join(file)) }
    end

    def all_available?
      # Check if all raw spec files exist
      SPEC_FILES.all? { |file| File.exist?(raw_specs_path.join(file)) }
    end

    def missing_specs
      SPEC_FILES.reject { |file| File.exist?(raw_specs_path.join(file)) }
    end

    def status
      if all_available?
        :ready
      elsif available?
        :partial
      else
        :unavailable
      end
    end

    def status_message
      case status
      when :ready
        "Specs are synced and ready"
      when :partial
        "Some specs are missing: #{missing_specs.join(", ")}"
      when :unavailable
        "Specs have not been synced yet. Run initial sync first."
      end
    end

    private

    def raw_specs_path
      Rails.root.join("storage", "specs", "raw")
    end
  end
end
