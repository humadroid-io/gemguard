class RegenerateFilteredSpecsJob < ApplicationJob
  queue_as :default

  SPEC_TYPES = {
    all: "specs.4.8.gz",
    latest: "latest_specs.4.8.gz",
    prerelease: "prerelease_specs.4.8.gz"
  }.freeze

  def perform(options = {})
    type = (options[:type] || options["type"] || :all).to_sym
    Rails.logger.info("RegenerateFilteredSpecsJob: Regenerating #{type} specs")

    raw_path = raw_specs_path.join(SPEC_TYPES[type])
    unless File.exist?(raw_path)
      Rails.logger.warn("RegenerateFilteredSpecsJob: No raw specs found at #{raw_path}")
      return
    end

    raw_data = File.binread(raw_path)
    current_specs = parse_specs(raw_data)

    build_filtered_specs(type, current_specs)
    Rails.logger.info("RegenerateFilteredSpecsJob: Completed regeneration for #{type}")
  end

  private

  def parse_specs(gzipped_data)
    RubygemsClient.parse_specs(gzipped_data)
  end

  def build_filtered_specs(type, current_specs)
    # Get active quarantined versions as a set for fast lookup
    quarantined_set = QuarantinedVersion.active.pluck(:name, :version, :platform).to_set

    # Get blocked versions from GemVersion
    blocked_set = GemVersion.blocked
      .joins(:gem_package)
      .pluck("gem_packages.name", :version, :platform)
      .to_set

    # Combine both sets - exclude quarantined AND blocked
    excluded_set = quarantined_set | blocked_set

    # Filter out excluded versions
    filtered_specs = current_specs.reject do |name, version, platform|
      platform_str = platform.to_s.presence || "ruby"
      excluded_set.include?([name, version.to_s, platform_str])
    end

    removed_count = current_specs.size - filtered_specs.size
    Rails.logger.info("RegenerateFilteredSpecsJob: Filtered #{removed_count} versions from specs")

    # Build gzipped Marshal data
    filtered_data = build_gzipped_specs(filtered_specs)

    # Save filtered specs for serving
    path = filtered_specs_path.join(SPEC_TYPES[type])
    atomic_write(path, filtered_data)
    Rails.logger.info("RegenerateFilteredSpecsJob: Saved filtered specs to #{path}")
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
