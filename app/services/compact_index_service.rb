class CompactIndexService
  LEGACY_SPEC_FILES = %w[specs.4.8.gz latest_specs.4.8.gz prerelease_specs.4.8.gz].freeze

  class << self
    def sync_versions
      new.sync_versions
    end

    def sync_info(gem_name)
      new.sync_info(gem_name)
    end

    def sync_names
      new.sync_names
    end

    def regenerate_versions
      new.regenerate_versions
    end

    def storage_path
      Rails.root.join("storage", "compact_index")
    end

    def raw_storage_path
      Rails.root.join("storage", "compact_index", "raw")
    end
  end

  def sync_versions
    upstream_url = "#{Setting.upstream_source}/versions"
    response = fetch_with_etag(upstream_url, raw_versions_path)

    return false unless response

    if response.is_a?(String)
      # Got new content - save raw and filter
      track_new_versions_from_compact_index(response, previous_versions_entries)
      write_file(raw_versions_path, response)
      filtered = filter_versions(response)
      write_file(versions_path, filtered)
    elsif File.exist?(raw_versions_path)
      # 304 Not Modified - re-filter from raw (quarantine status may have changed)
      raw_content = File.read(raw_versions_path)
      filtered = filter_versions(raw_content)
      write_file(versions_path, filtered)
    end

    true
  rescue => e
    Rails.logger.error("CompactIndexService#sync_versions failed: #{e.message}")
    false
  end

  def regenerate_versions
    return false unless File.exist?(raw_versions_path)

    raw_content = File.read(raw_versions_path)
    filtered = filter_versions(raw_content)
    write_file(versions_path, filtered)

    Rails.logger.info("CompactIndexService: Regenerated versions from raw cache")
    true
  rescue => e
    Rails.logger.error("CompactIndexService#regenerate_versions failed: #{e.message}")
    false
  end

  def sync_info(gem_name)
    return false unless sync_versions

    upstream_url = "#{Setting.upstream_source}/info/#{gem_name}"
    info_file_path = info_path(gem_name)
    raw_info_file_path = raw_info_path(gem_name)

    response = fetch_with_etag(upstream_url, raw_info_file_path)

    return false unless response

    if response.is_a?(String)
      # Got new content - save raw and filter
      write_file(raw_info_file_path, response)
      filtered = filter_info(gem_name, response)
      write_file(info_file_path, filtered)
    elsif File.exist?(raw_info_file_path)
      # 304 Not Modified - re-filter from raw (quarantine status may have changed)
      raw_content = File.read(raw_info_file_path)
      filtered = filter_info(gem_name, raw_content)
      write_file(info_file_path, filtered)
    end

    true
  rescue => e
    Rails.logger.error("CompactIndexService#sync_info(#{gem_name}) failed: #{e.message}")
    false
  end

  def sync_names
    upstream_url = "#{Setting.upstream_source}/names"

    response = HTTParty.get(upstream_url, timeout: 60)
    return false unless response.success?

    # Names file doesn't need filtering - just gem names
    write_file(names_path, response.body)
    true
  rescue => e
    Rails.logger.error("CompactIndexService#sync_names failed: #{e.message}")
    false
  end

  private

  def fetch_with_etag(url, local_path)
    headers = {}

    if File.exist?(local_path)
      etag_path = "#{local_path}.etag"
      headers["If-None-Match"] = File.read(etag_path) if File.exist?(etag_path)
    end

    response = HTTParty.get(url, headers: headers, timeout: 120)

    if response.code == 304
      :not_modified
    elsif response.success?
      # Save ETag for future requests
      if response.headers["etag"]
        FileUtils.mkdir_p(File.dirname(local_path))
        File.write("#{local_path}.etag", response.headers["etag"])
      end
      response.body
    else
      Rails.logger.warn("Compact index fetch failed: #{url} returned #{response.code}")
      nil
    end
  end

  def filter_versions(content)
    excluded = load_excluded_versions
    return content if excluded.empty?

    lines = content.lines
    header_end = lines.index { |l| l.strip == "---" }

    if header_end
      header = lines[0..header_end]
      body = lines[(header_end + 1)..]
    else
      header = []
      body = lines
    end

    filtered_body = body.filter_map do |line|
      filter_versions_line(line, excluded)
    end

    (header + filtered_body).join
  end

  def filter_versions_line(line, excluded)
    return line if line.strip.empty? || line.start_with?("#")

    parts = line.split(" ")
    return line if parts.size < 2

    gem_name = parts[0]
    versions_str = parts[1]

    # Check if any versions of this gem are quarantined
    gem_excluded = excluded[gem_name]
    return line unless gem_excluded&.any?

    # Filter out quarantined versions
    versions = versions_str.split(",")
    filtered_versions = versions.reject { |version_token| excluded_version_token?(gem_excluded, version_token) }

    return nil if filtered_versions.empty?

    filtered_checksum = filtered_info_checksum(gem_name)
    return nil unless filtered_checksum

    line_ending = line.end_with?("\n") ? "\n" : ""
    "#{gem_name} #{filtered_versions.join(",")} #{filtered_checksum}#{line_ending}"
  end

  def filter_info(gem_name, content)
    excluded = load_excluded_versions[gem_name]
    return content unless excluded&.any?

    lines = content.lines
    header_end = lines.index { |l| l.strip == "---" }

    if header_end
      header = lines[0..header_end]
      body = lines[(header_end + 1)..]
    else
      header = []
      body = lines
    end

    filtered_body = body.reject do |line|
      next false if line.strip.empty? || line.start_with?("#")

      # First part of line is version (possibly with platform)
      version_part = line.split(" ").first
      next false unless version_part

      excluded_version_token?(excluded, version_part)
    end

    (header + filtered_body).join
  end

  def excluded_version_token?(excluded_versions, version_token)
    excluded_versions.any? do |version, platform|
      version_token == if platform == "ruby"
        version
      else
        "#{version}-#{platform}"
      end
    end
  end

  def filtered_info_checksum(gem_name)
    @filtered_info_checksums ||= {}
    return @filtered_info_checksums[gem_name] if @filtered_info_checksums.key?(gem_name)

    raw_content = ensure_raw_info_content(gem_name)
    unless raw_content
      Rails.logger.warn("CompactIndexService: Could not load raw info for #{gem_name}, omitting from filtered versions")
      @filtered_info_checksums[gem_name] = nil
      return nil
    end

    filtered_content = filter_info(gem_name, raw_content)
    write_file(info_path(gem_name), filtered_content)

    @filtered_info_checksums[gem_name] = Digest::MD5.hexdigest(filtered_content)
  end

  def ensure_raw_info_content(gem_name)
    raw_path = raw_info_path(gem_name)
    return File.read(raw_path) if File.exist?(raw_path)

    upstream_url = "#{Setting.upstream_source}/info/#{gem_name}"
    response = fetch_with_etag(upstream_url, raw_path)

    case response
    when String
      write_file(raw_path, response)
      response
    when :not_modified
      File.exist?(raw_path) ? File.read(raw_path) : nil
    end
  end

  def load_excluded_versions
    @excluded_versions ||= begin
      result = Hash.new { |h, k| h[k] = Set.new }

      QuarantinedVersion.active.find_each do |qv|
        result[qv.name] << [qv.version, qv.platform]
      end

      GemVersion.blocked.joins(:gem_package).find_each do |gem_version|
        result[gem_version.gem_package.name] << [gem_version.version, gem_version.platform]
      end

      result
    end
  end

  def track_new_versions_from_compact_index(current_content, previous_entries)
    return unless previous_entries&.any?
    return if within_baseline_grace_period?

    current_entries = parse_versions_entries(current_content)
    new_entries = current_entries - previous_entries
    return if new_entries.empty?

    now = Time.current
    records = new_entries.map do |name, version, platform|
      {
        name: name,
        version: version,
        platform: platform,
        first_seen_at: now,
        created_at: now,
        updated_at: now
      }
    end

    QuarantinedVersion.upsert_all(records, unique_by: [:name, :version, :platform])
    ResolverMetadataInvalidator.invalidate!(gem_names: new_entries.map(&:first).uniq, compact: false)
    enqueue_metadata_refresh_for_tracked_gems(new_entries)
    @excluded_versions = nil

    Rails.logger.info("CompactIndexService: Added #{records.size} compact index versions to quarantine")
  end

  def previous_versions_entries
    return parse_versions_entries(File.read(raw_versions_path)) if File.exist?(raw_versions_path)

    legacy_specs_entries
  end

  def legacy_specs_entries
    entries = Set.new

    LEGACY_SPEC_FILES.each do |filename|
      path = Rails.root.join("storage", "specs", "raw", filename)
      next unless File.exist?(path)

      RubygemsClient.parse_specs(File.binread(path)).each do |name, version, platform|
        entries << [name, version.to_s, normalize_platform(platform)]
      end
    end

    entries
  end

  def parse_versions_entries(content)
    entries = Set.new
    body_lines(content).each do |line|
      next if line.strip.empty? || line.start_with?("#")

      parts = line.split(" ")
      next if parts.size < 2

      name = parts[0]
      parts[1].split(",").each do |version_token|
        version, platform = parse_version_token(version_token)
        entries << [name, version, platform]
      end
    end

    entries
  end

  def body_lines(content)
    lines = content.lines
    header_end = lines.index { |line| line.strip == "---" }
    header_end ? lines[(header_end + 1)..] : lines
  end

  def parse_version_token(version_token)
    token = version_token.to_s.strip

    platform = known_platforms.find { |candidate| token.end_with?("-#{candidate}") }
    return [token.delete_suffix("-#{platform}"), platform] if platform

    [token, "ruby"]
  end

  def normalize_platform(platform)
    platform.to_s.presence || "ruby"
  end

  def known_platforms
    @known_platforms ||= %w[
      x86_64-linux x86_64-linux-gnu x86_64-linux-musl
      aarch64-linux aarch64-linux-gnu aarch64-linux-musl
      arm-linux arm-linux-gnu arm-linux-musl
      x86_64-darwin arm64-darwin
      x64-mingw32 x64-mingw-ucrt
      java jruby
    ]
  end

  def enqueue_metadata_refresh_for_tracked_gems(entries)
    gem_names = entries.map(&:first).uniq
    tracked_names = GemPackage.tracked.where(name: gem_names).pluck(:name)
    return if tracked_names.empty?

    RefreshGemMetadataJob.perform_later(tracked_names)
  end

  def within_baseline_grace_period?
    baseline_imported_at = Setting.get(:baseline_imported_at)
    return false unless baseline_imported_at

    imported_at = Time.parse(baseline_imported_at)
    Time.current < imported_at + SyncSpecsJob::BASELINE_GRACE_PERIOD
  rescue ArgumentError
    false
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def versions_path
    self.class.storage_path.join("versions")
  end

  def raw_versions_path
    self.class.raw_storage_path.join("versions")
  end

  def names_path
    self.class.storage_path.join("names")
  end

  def info_path(gem_name)
    self.class.storage_path.join("info", gem_name)
  end

  def raw_info_path(gem_name)
    self.class.raw_storage_path.join("info", gem_name)
  end
end
