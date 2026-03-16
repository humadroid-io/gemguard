# frozen_string_literal: true

# Syncs gem specs from RubyGems.org and detects new versions for quarantine.
#
# This job:
# 1. Downloads current specs from RubyGems.org
# 2. Compares against previous specs to detect NEW versions
# 3. Adds new versions to quarantined_versions table
# 4. Saves raw specs (for next diff)
# 5. Builds filtered specs excluding quarantined/blocked versions
#
# The filtered specs are what Bundler sees - quarantined gems are invisible.
class SyncSpecsJob < ApplicationJob
  queue_as :default

  SPEC_TYPES = {
    all: "specs.4.8.gz",
    latest: "latest_specs.4.8.gz",
    prerelease: "prerelease_specs.4.8.gz"
  }.freeze

  # Grace period after baseline import to avoid false positives from RubyGems CDN differences
  BASELINE_GRACE_PERIOD = 10.minutes

  def perform(options = {})
    type = (options[:type] || options["type"] || :all).to_sym
    Rails.logger.info("SyncSpecsJob: Starting sync for #{type}")

    # 1. Download current specs from RubyGems
    current_data = RubygemsClient.fetch_specs(type)
    unless current_data
      Rails.logger.error("SyncSpecsJob: Failed to fetch #{type} specs")
      return
    end

    current_specs = parse_specs(current_data)
    if current_specs.empty?
      Rails.logger.warn("SyncSpecsJob: Empty specs received for #{type}")
      return
    end

    Rails.logger.info("SyncSpecsJob: Downloaded #{current_specs.size} entries for #{type}")

    # 2. Load previous specs and detect new versions
    previous_specs = load_previous_specs(type)

    if previous_specs.present?
      new_versions = detect_new_versions(previous_specs, current_specs)

      if new_versions.any?
        # Skip quarantine tracking during grace period after baseline import
        # RubyGems CDN may have slight differences, causing false positives
        if within_baseline_grace_period?
          Rails.logger.info("SyncSpecsJob: Skipping quarantine tracking (within grace period after baseline import)")
        else
          # 3. Add new versions to quarantine
          track_new_versions(new_versions)
          enqueue_metadata_refresh_for_tracked_gems(new_versions)
        end
      end
    else
      Rails.logger.info("SyncSpecsJob: No previous specs found for #{type} (first sync or baseline)")
    end

    # 4. Save raw specs (for next diff)
    save_raw_specs(type, current_data)

    # 5. Build and save filtered specs
    build_filtered_specs(type, current_specs)

    Rails.logger.info("SyncSpecsJob: Completed sync for #{type}")
  end

  private

  def parse_specs(gzipped_data)
    RubygemsClient.parse_specs(gzipped_data)
  end

  def load_previous_specs(type)
    path = raw_specs_path.join(SPEC_TYPES[type])
    return nil unless File.exist?(path)

    data = File.binread(path)
    parse_specs(data)
  rescue => e
    Rails.logger.warn("SyncSpecsJob: Failed to load previous specs: #{e.message}")
    nil
  end

  def detect_new_versions(previous_specs, current_specs)
    # Build a set of previous versions for fast lookup
    previous_set = previous_specs.map do |name, version, platform|
      [name, version.to_s, normalize_platform(platform)]
    end.to_set

    # Find versions in current that weren't in previous
    new_versions = current_specs.reject do |name, version, platform|
      previous_set.include?([name, version.to_s, normalize_platform(platform)])
    end

    Rails.logger.info("SyncSpecsJob: Detected #{new_versions.size} new versions")
    new_versions
  end

  def track_new_versions(versions)
    return if versions.empty?

    records = versions.map do |name, version, platform|
      {
        name: name,
        version: version.to_s,
        platform: normalize_platform(platform),
        first_seen_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Bulk upsert - ignore duplicates (may already be tracked)
    QuarantinedVersion.upsert_all(
      records,
      unique_by: [:name, :version, :platform]
    )

    Rails.logger.info("SyncSpecsJob: Added #{records.size} versions to quarantine")
  end

  def enqueue_metadata_refresh_for_tracked_gems(versions)
    gem_names = versions.map(&:first).uniq
    tracked_names = GemPackage.tracked.where(name: gem_names).pluck(:name)
    return if tracked_names.empty?

    RefreshGemMetadataJob.perform_later(tracked_names)
    Rails.logger.info("SyncSpecsJob: Enqueued metadata refresh for #{tracked_names.size} tracked gems")
  end

  def save_raw_specs(type, data)
    path = raw_specs_path.join(SPEC_TYPES[type])
    atomic_write(path, data)
    Rails.logger.info("SyncSpecsJob: Saved raw specs to #{path}")
  end

  def build_filtered_specs(type, current_specs)
    # Get blocked versions from gem_versions table
    blocked_set = GemVersion.blocked
      .joins(:gem_package)
      .pluck("gem_packages.name", :version, :platform)
      .to_set

    # Get actively quarantined versions
    quarantined_set = QuarantinedVersion.active
      .pluck(:name, :version, :platform)
      .to_set

    # Combine exclusion sets
    excluded_set = blocked_set | quarantined_set

    # Filter out excluded versions
    filtered_specs = current_specs.reject do |name, version, platform|
      excluded_set.include?([name, version.to_s, normalize_platform(platform)])
    end

    excluded_count = current_specs.size - filtered_specs.size
    if excluded_count > 0
      Rails.logger.info("SyncSpecsJob: Excluded #{excluded_count} versions (#{blocked_set.size} blocked, #{quarantined_set.size} quarantined)")
    end

    # Build gzipped Marshal data
    filtered_data = build_gzipped_specs(filtered_specs)

    # Save filtered specs
    path = filtered_specs_path.join(SPEC_TYPES[type])
    atomic_write(path, filtered_data)
    Rails.logger.info("SyncSpecsJob: Saved filtered specs to #{path} (#{filtered_specs.size} versions)")
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

  def normalize_platform(platform)
    platform.to_s.presence || "ruby"
  end

  def within_baseline_grace_period?
    baseline_imported_at = Setting.get(:baseline_imported_at)
    return false unless baseline_imported_at

    imported_at = Time.parse(baseline_imported_at)
    Time.current < imported_at + BASELINE_GRACE_PERIOD
  rescue ArgumentError
    false
  end

  def raw_specs_path
    Rails.root.join("storage", "specs", "raw")
  end

  def filtered_specs_path
    Rails.root.join("storage", "specs")
  end
end
