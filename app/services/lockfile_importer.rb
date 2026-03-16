class LockfileImporter
  Result = Struct.new(:imported, :existing, :queued, :app_gems, keyword_init: true)

  def self.import(content, managed_app: nil)
    new(content, managed_app: managed_app).import
  end

  def initialize(content, managed_app: nil)
    @content = content
    @managed_app = managed_app
  end

  def import
    specs, direct_dependencies = parse_lockfile
    imported = 0
    existing = 0
    gem_names = Set.new
    resolved_versions = {}

    specs.each do |spec|
      name = spec.name
      version = spec.version.to_s
      platform = normalize_platform(spec.platform)
      gem_names << name

      gem_package = GemPackage.find_or_create_by!(name: name)
      gem_version = gem_package.versions.find_or_initialize_by(
        version: version,
        platform: platform
      )

      if gem_version.new_record?
        gem_version.status = :approved
        gem_version.first_seen_at = Time.current
        gem_version.save!
        imported += 1
      else
        existing += 1
      end

      resolved_versions[[name, platform]] = gem_version
      resolved_versions[[name, "ruby"]] ||= gem_version if platform == "ruby"
    rescue => e
      Rails.logger.error("LockfileImporter error for #{name}: #{e.message}")
    end

    sync_managed_app!(specs, direct_dependencies, resolved_versions) if @managed_app

    # Queue ONE background job to refresh all imported gems
    ImportLockfileJob.perform_later(gem_names.to_a)

    Result.new(imported: imported, existing: existing, queued: gem_names.size, app_gems: @managed_app ? specs.size : 0)
  end

  private

  def parse_lockfile
    parser = Bundler::LockfileParser.new(@content)
    [parser.specs, parser.dependencies.keys.to_set]
  end

  def sync_managed_app!(specs, direct_dependencies, resolved_versions)
    current_gem_version_ids = resolved_versions.values.uniq.map(&:id)

    @managed_app.transaction do
      @managed_app.app_dependency_edges.delete_all

      current_gem_version_ids.each do |gem_version_id|
        direct = specs.any? do |spec|
          resolved_versions[[spec.name, normalize_platform(spec.platform)]]&.id == gem_version_id &&
            direct_dependencies.include?(spec.name)
        end

        app_gem_version = @managed_app.app_gem_versions.find_or_initialize_by(gem_version_id: gem_version_id)
        app_gem_version.direct = direct
        app_gem_version.save!
      end

      @managed_app.app_gem_versions.where.not(gem_version_id: current_gem_version_ids).delete_all

      specs.each do |spec|
        parent = resolved_versions[[spec.name, normalize_platform(spec.platform)]]
        next unless parent

        spec.dependencies.each do |dependency|
          child = resolve_dependency_version(resolved_versions, dependency.name)
          next unless child

          @managed_app.app_dependency_edges.create!(
            parent_gem_version: parent,
            child_gem_version: child,
            requirement: dependency.requirement.to_s
          )
        end
      end
    end
  end

  def resolve_dependency_version(resolved_versions, dependency_name)
    resolved_versions[[dependency_name, "ruby"]] ||
      resolved_versions.find { |(name, _platform), _version| name == dependency_name }&.last
  end

  def normalize_platform(platform)
    platform_string = platform.to_s
    platform_string.present? ? platform_string : "ruby"
  end
end
