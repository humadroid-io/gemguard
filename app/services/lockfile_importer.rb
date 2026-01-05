class LockfileImporter
  Result = Struct.new(:imported, :existing, :queued, keyword_init: true)

  def self.import(content)
    new(content).import
  end

  def initialize(content)
    @content = content
  end

  def import
    gems = parse_lockfile
    imported = 0
    existing = 0
    gem_names = Set.new

    gems.each do |name, version, platform|
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
    rescue => e
      Rails.logger.error("LockfileImporter error for #{name}: #{e.message}")
    end

    # Queue ONE background job to refresh all imported gems
    ImportLockfileJob.perform_later(gem_names.to_a)

    Result.new(imported: imported, existing: existing, queued: gem_names.size)
  end

  private

  def parse_lockfile
    gems = []
    in_gems_section = false
    in_specs = false

    @content.each_line do |line|
      if line.strip == "GEM"
        in_gems_section = true
        in_specs = false
        next
      end

      if in_gems_section && line.strip == "specs:"
        in_specs = true
        next
      end

      if line.strip.empty? || (line =~ /^[A-Z]+$/ && line.strip != "GEM")
        in_gems_section = false if in_gems_section
        in_specs = false
        next
      end

      next unless in_gems_section && in_specs

      # Match gem entries: "    rails (7.1.0)" or "    nokogiri (1.16.0-x86_64-linux)"
      # Only top-level gems (4 spaces), skip dependencies (6+ spaces)
      if line =~ /^    (\S+)\s+\(([^)]+)\)$/
        name = $1
        version_str = $2

        version, platform = parse_version_platform(version_str)
        gems << [name, version, platform]
      end
    end

    gems
  end

  def parse_version_platform(version_str)
    platform_patterns = %w[
      x86_64-linux x86_64-linux-gnu x86_64-linux-musl
      aarch64-linux aarch64-linux-gnu aarch64-linux-musl
      x86_64-darwin arm64-darwin
      x64-mingw32 x64-mingw-ucrt
      java jruby
    ]

    platform_patterns.each do |platform|
      if version_str.end_with?("-#{platform}")
        version = version_str.chomp("-#{platform}")
        return [version, platform]
      end
    end

    if version_str =~ /^(.+)-((?:x86_64|arm64)-darwin-\d+)$/
      return [$1, $2]
    end

    [version_str, "ruby"]
  end
end
