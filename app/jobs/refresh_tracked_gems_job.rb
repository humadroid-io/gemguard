# frozen_string_literal: true

class RefreshTrackedGemsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("RefreshTrackedGemsJob: Starting refresh of tracked gems")

    tracked_count = 0
    new_versions_count = 0

    # Only refresh gems that have been explicitly tracked (downloaded by the organization)
    # This excludes gems from baseline/dump imports that haven't been used
    GemPackage.tracked.find_each do |gem_package|
      tracked_count += 1
      new_versions_count += refresh_gem(gem_package)
    end

    Rails.logger.info("RefreshTrackedGemsJob: Checked #{tracked_count} tracked gems, found #{new_versions_count} new versions")

    # Regenerate specs if new versions were found
    if new_versions_count > 0
      %i[all latest prerelease].each do |type|
        RegenerateFilteredSpecsJob.perform_later(type: type)
      end
    end
  end

  private

  def refresh_gem(gem_package)
    versions = fetch_versions(gem_package.name)
    return 0 unless versions

    new_count = 0

    # Note: RubyGems API only returns non-yanked versions
    # Yanked versions are simply excluded from the response
    versions.each do |version_info|
      version = version_info["number"]
      platform = version_info["platform"] || "ruby"
      published_at = parse_timestamp(version_info["created_at"])

      # Skip if we already have this version
      next if gem_package.versions.exists?(version: version, platform: platform)

      # Determine if it should be quarantined
      is_new = published_at && published_at > Setting.quarantine_period.ago
      status = is_new ? :quarantined : :approved

      gem_package.versions.create!(
        version: version,
        platform: platform,
        published_at: published_at,
        first_seen_at: Time.current,
        status: status
      )

      # Also add to QuarantinedVersion table if quarantined
      if status == :quarantined
        QuarantinedVersion.find_or_create_by!(
          name: gem_package.name,
          version: version,
          platform: platform
        ) do |qv|
          qv.first_seen_at = Time.current
        end
      end

      new_count += 1
      Rails.logger.info("RefreshTrackedGemsJob: Found new version #{gem_package.name}-#{version} (#{status})")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Race condition or invalid data, skip
    end

    new_count
  end

  def fetch_versions(gem_name)
    response = HTTParty.get(
      "https://rubygems.org/api/v1/versions/#{gem_name}.json",
      timeout: 10,
      headers: {"User-Agent" => "GemGuard/1.0"}
    )

    return nil unless response.success?

    JSON.parse(response.body)
  rescue => e
    Rails.logger.warn("RefreshTrackedGemsJob: Failed to fetch versions for #{gem_name}: #{e.message}")
    nil
  end

  def parse_timestamp(value)
    return nil if value.nil?

    Time.parse(value)
  rescue ArgumentError
    nil
  end
end
