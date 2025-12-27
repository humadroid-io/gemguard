# frozen_string_literal: true

class GemRefreshService
  attr_reader :gem_package, :errors

  def initialize(gem_package)
    @gem_package = gem_package
    @errors = []
  end

  def call
    refresh_gem_info
    refresh_versions

    errors.empty?
  end

  def new_versions_count
    @new_versions_count || 0
  end

  private

  def refresh_gem_info
    gem_info = RubygemsClient.fetch_gem_info(gem_package.name)

    unless gem_info
      errors << "Could not fetch gem info from RubyGems"
      return
    end

    gem_package.update!(
      info: gem_info["info"],
      homepage_url: gem_info["homepage_uri"],
      downloads_count: gem_info["downloads"]
    )
  rescue StandardError => e
    errors << "Failed to update gem info: #{e.message}"
  end

  def refresh_versions
    versions_data = fetch_versions
    return if versions_data.nil?

    @new_versions_count = 0

    # Note: RubyGems API only returns non-yanked versions
    # Yanked versions are simply excluded from the response
    versions_data.each do |version_info|
      create_or_update_version(version_info)
    end
  end

  def fetch_versions
    response = HTTParty.get(
      "https://rubygems.org/api/v1/versions/#{gem_package.name}.json",
      timeout: 30,
      headers: { "User-Agent" => "GemGuard/1.0" }
    )

    unless response.success?
      errors << "Could not fetch versions from RubyGems (HTTP #{response.code})"
      return nil
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    errors << "Invalid JSON response: #{e.message}"
    nil
  rescue StandardError => e
    errors << "Failed to fetch versions: #{e.message}"
    nil
  end

  def create_or_update_version(version_info)
    version = version_info["number"]
    platform = version_info["platform"] || "ruby"
    published_at = parse_timestamp(version_info["created_at"])

    existing = gem_package.versions.find_by(version: version, platform: platform)

    if existing
      # Update existing version's published_at if missing
      existing.update!(published_at: published_at) if existing.published_at.nil? && published_at
    else
      # Create new version
      is_new = published_at && published_at > Setting.quarantine_period.ago
      status = is_new ? :quarantined : :approved

      gem_package.versions.create!(
        version: version,
        platform: platform,
        published_at: published_at,
        first_seen_at: Time.current,
        status: status
      )

      # Add to QuarantinedVersion if quarantined
      if status == :quarantined
        QuarantinedVersion.find_or_create_by!(
          name: gem_package.name,
          version: version,
          platform: platform
        ) do |qv|
          qv.first_seen_at = Time.current
        end
      end

      @new_versions_count += 1
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    # Race condition or validation error, log and continue
    Rails.logger.warn("GemRefreshService: Could not create version #{version}: #{e.message}")
  end

  def parse_timestamp(value)
    return nil if value.nil?

    Time.parse(value)
  rescue ArgumentError
    nil
  end
end
