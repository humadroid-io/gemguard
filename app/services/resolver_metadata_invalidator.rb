class ResolverMetadataInvalidator
  SPEC_FILES = %w[specs.4.8.gz latest_specs.4.8.gz prerelease_specs.4.8.gz].freeze

  def self.invalidate!(gem_names:, legacy: true, compact: true)
    new(gem_names, legacy: legacy, compact: compact).invalidate!
  end

  def initialize(gem_names, legacy:, compact:)
    @gem_names = Array(gem_names).compact_blank.uniq
    @legacy = legacy
    @compact = compact
  end

  def invalidate!
    invalidate_legacy_specs if legacy
    invalidate_compact_index if compact
  end

  private

  attr_reader :gem_names, :legacy, :compact

  def invalidate_legacy_specs
    SPEC_FILES.each do |filename|
      FileUtils.rm_f(Rails.root.join("storage", "specs", filename))
    end
  end

  def invalidate_compact_index
    FileUtils.rm_f(Rails.root.join("storage", "compact_index", "versions"))

    gem_names.each do |gem_name|
      info_path = Rails.root.join("storage", "compact_index", "info", gem_name)
      FileUtils.rm_f(info_path)
      FileUtils.rm_f("#{info_path}.etag")
    end
  end
end
