class CompactIndexService
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

    def storage_path
      Rails.root.join("storage", "compact_index")
    end
  end

  def sync_versions
    upstream_url = "#{Setting.upstream_source}/versions"
    response = fetch_with_etag(upstream_url, versions_path)

    return false unless response

    if response.is_a?(String)
      # Got new content, filter and save
      filtered = filter_versions(response)
      write_file(versions_path, filtered)
    elsif File.exist?(versions_path)
      # 304 Not Modified, touch the file
      FileUtils.touch(versions_path)
    end

    true
  rescue => e
    Rails.logger.error("CompactIndexService#sync_versions failed: #{e.message}")
    false
  end

  def sync_info(gem_name)
    upstream_url = "#{Setting.upstream_source}/info/#{gem_name}"
    info_file_path = info_path(gem_name)

    response = fetch_with_etag(upstream_url, info_file_path)

    return false unless response

    if response.is_a?(String)
      # Got new content, filter and save
      filtered = filter_info(gem_name, response)
      write_file(info_file_path, filtered)
    elsif File.exist?(info_file_path)
      # 304 Not Modified, touch the file
      FileUtils.touch(info_file_path)
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
    quarantined = load_quarantined_versions
    return content if quarantined.empty?

    lines = content.lines
    header_end = lines.index { |l| l.strip == "---" }

    if header_end
      header = lines[0..header_end]
      body = lines[(header_end + 1)..]
    else
      header = []
      body = lines
    end

    filtered_body = body.map do |line|
      filter_versions_line(line, quarantined)
    end.compact

    (header + filtered_body).join
  end

  def filter_versions_line(line, quarantined)
    return line if line.strip.empty? || line.start_with?("#")

    parts = line.split(" ")
    return line if parts.size < 2

    gem_name = parts[0]
    versions_str = parts[1]
    checksum = parts[2]

    # Check if any versions of this gem are quarantined
    gem_quarantined = quarantined[gem_name]
    return line unless gem_quarantined

    # Filter out quarantined versions
    versions = versions_str.split(",")
    filtered_versions = versions.reject do |v|
      # Version might have platform suffix like "1.0.0-java"
      version, platform = parse_version_platform(v)
      platform ||= "ruby"
      gem_quarantined.include?([version, platform])
    end

    return nil if filtered_versions.empty?

    # Rebuild line with filtered versions
    # Note: checksum would ideally be recalculated, but we keep original for simplicity
    "#{gem_name} #{filtered_versions.join(",")} #{checksum}"
  end

  def filter_info(gem_name, content)
    quarantined = load_quarantined_versions[gem_name]
    return content unless quarantined&.any?

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

      version, platform = parse_version_platform(version_part)
      platform ||= "ruby"
      quarantined.include?([version, platform])
    end

    (header + filtered_body).join
  end

  def parse_version_platform(version_str)
    # Handle versions like "1.0.0" or "1.0.0-x86_64-linux"
    # Platform comes after version, separated by hyphen, but version can have hyphens too
    # Strategy: platform starts with known patterns or after version pattern ends

    # Simple approach: if it matches version-platform pattern
    if version_str =~ /^(.+?)-(java|x86_64-linux|x86_64-darwin|arm64-darwin|x64-mingw.*|mswin.*)$/
      [$1, $2]
    else
      [version_str, nil]
    end
  end

  def load_quarantined_versions
    @quarantined_versions ||= begin
      result = Hash.new { |h, k| h[k] = Set.new }

      QuarantinedVersion.active.find_each do |qv|
        result[qv.name] << [qv.version, qv.platform]
      end

      result
    end
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def versions_path
    self.class.storage_path.join("versions")
  end

  def names_path
    self.class.storage_path.join("names")
  end

  def info_path(gem_name)
    self.class.storage_path.join("info", gem_name)
  end
end
