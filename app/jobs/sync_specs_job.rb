class SyncSpecsJob < ApplicationJob
  queue_as :default

  SPEC_TYPES = {
    all: "specs.4.8.gz",
    latest: "latest_specs.4.8.gz",
    prerelease: "prerelease_specs.4.8.gz"
  }.freeze

  def perform(options = {})
    type = (options[:type] || options["type"] || :all).to_sym
    Rails.logger.info("SyncSpecsJob: Starting sync for #{type}")

    raw_data = RubygemsClient.fetch_specs(type)
    return unless raw_data

    current_specs = parse_specs(raw_data)
    return if current_specs.empty?

    # Save raw specs
    save_raw_specs(type, raw_data)

    # Build and save filtered specs (excludes blocked + quarantined)
    build_filtered_specs(type, current_specs)

    Rails.logger.info("SyncSpecsJob: Completed sync for #{type}")
  end

  private

  def parse_specs(gzipped_data)
    RubygemsClient.parse_specs(gzipped_data)
  end

  def save_raw_specs(type, data)
    path = raw_specs_path.join(SPEC_TYPES[type])
    atomic_write(path, data)
    Rails.logger.info("SyncSpecsJob: Saved raw specs to #{path}")
  end

  def build_filtered_specs(type, current_specs)
    # Get blocked versions
    blocked_set = GemVersion.blocked
      .joins(:gem_package)
      .pluck("gem_packages.name", :version, :platform)
      .to_set

    # Get active quarantined versions
    quarantined_set = QuarantinedVersion.active
      .pluck(:name, :version, :platform)
      .to_set

    # Exclude blocked and actively quarantined
    excluded_set = blocked_set | quarantined_set

    # Filter out excluded versions - unknown gems pass through
    filtered_specs = current_specs.reject do |name, version, platform|
      platform_str = platform.to_s.presence || "ruby"
      excluded_set.include?([name, version.to_s, platform_str])
    end

    excluded_count = current_specs.size - filtered_specs.size
    if excluded_count > 0
      Rails.logger.info("SyncSpecsJob: Excluded #{excluded_count} versions (blocked/quarantined)")
    end

    # Build gzipped Marshal data
    filtered_data = build_gzipped_specs(filtered_specs)

    # Save filtered specs for serving
    path = filtered_specs_path.join(SPEC_TYPES[type])
    atomic_write(path, filtered_data)
    Rails.logger.info("SyncSpecsJob: Saved filtered specs to #{path}")
  end

  def build_gzipped_specs(specs)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    io.string
  end

  def atomic_write(path, data)
    FileUtils.mkdir_p(File.dirname(path))
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
