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
    return line unless gem_quarantined&.any?

    # Filter out quarantined versions
    versions = versions_str.split(",")
    filtered_versions = versions.reject { |version_token| quarantined_version_token?(gem_quarantined, version_token) }

    return nil if filtered_versions.empty?

    filtered_checksum = filtered_info_checksum(gem_name)
    return nil unless filtered_checksum

    "#{gem_name} #{filtered_versions.join(",")} #{filtered_checksum}"
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

      quarantined_version_token?(quarantined, version_part)
    end

    (header + filtered_body).join
  end

  def quarantined_version_token?(quarantined_versions, version_token)
    quarantined_versions.any? do |version, platform|
      version_token == version || version_token == "#{version}-#{platform}"
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
    else
      nil
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
