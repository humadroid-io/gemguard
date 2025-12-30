module GemVersionLookup
  extend ActiveSupport::Concern

  private

  def parse_gem_identifier(filename, extension)
    name = filename.chomp(extension)
    parts = name.split("-")

    return nil if parts.size < 2

    version_index = parts.rindex { |p| p.match?(/^\d/) }
    return nil unless version_index

    {
      name: parts[0...version_index].join("-"),
      version: parts[version_index],
      platform: parts[(version_index + 1)..].join("-").presence || "ruby"
    }
  end

  def find_or_fetch_gem_version(parsed)
    find_gem_version(parsed) || fetch_gem_from_upstream(parsed)
  end

  def find_gem_version(parsed)
    gem_package = GemPackage.find_by(name: parsed[:name])
    return nil unless gem_package

    gem_package.versions.find_by(version: parsed[:version], platform: parsed[:platform])
  end

  def fetch_gem_from_upstream(parsed)
    gem_info = RubygemsClient.fetch_gem_info(parsed[:name])
    return nil unless gem_info

    version_info = RubygemsClient.fetch_version_info(parsed[:name], parsed[:version])
    return nil unless version_info

    create_gem_version(parsed, gem_info, version_info)
  end

  def create_gem_version(parsed, gem_info, version_info)
    gem_package = GemPackage.find_or_create_by!(name: parsed[:name]) do |pkg|
      pkg.info = gem_info["info"]
      pkg.homepage_url = gem_info["homepage_uri"]
      pkg.downloads_count = gem_info["downloads"]
      configure_new_gem_package(pkg)
    end

    after_gem_package_found(gem_package)

    published_at = begin
      Time.parse(version_info["created_at"])
    rescue
      Time.current
    end

    # Check if already quarantined or if recently published (within quarantine period)
    is_quarantined = QuarantinedVersion.quarantined?(parsed[:name], parsed[:version], parsed[:platform]) ||
      published_at > Setting.quarantine_period.ago

    # GemVersion callback will create QuarantinedVersion if status is :quarantined
    gem_package.versions.create!(
      version: parsed[:version],
      platform: parsed[:platform],
      published_at: published_at,
      first_seen_at: Time.current,
      status: is_quarantined ? :quarantined : :approved
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_gem_version(parsed)
  end

  def handle_gem_version_response(gem_version)
    if gem_version.nil?
      head :not_found
    elsif gem_version.blocked?
      head :forbidden
    elsif gem_version.actively_quarantined?
      response.headers["Retry-After"] = "300"
      render plain: "Gem #{gem_versiom.gem_package} in version #{gem_version} is quarantined. Re-run bundle install to refresh specs.",
        status: :service_unavailable
    else
      yield gem_version
    end
  end

  # Hook methods - override in controllers for custom behavior
  def configure_new_gem_package(pkg)
    # Default: no-op
  end

  def after_gem_package_found(gem_package)
    # Default: no-op
  end
end
