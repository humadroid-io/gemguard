module Api
  class DependenciesController < BaseController
    def index
      gem_names = requested_gems
      return head :bad_request if gem_names.empty?
      return head :bad_gateway unless refresh_quarantine_state(gem_names)

      payload = RubygemsClient.fetch_dependencies(gem_names)
      return head :bad_gateway unless payload

      dependencies = RubygemsClient.parse_dependencies(payload)
      filtered = filter_dependencies(dependencies)

      AuditLog.log_spec_request(request: request, spec_type: "api/v1/dependencies")
      send_data Marshal.dump(filtered), type: "application/octet-stream", disposition: "inline"
    end

    private

    def requested_gems
      params[:gems].to_s.split(",").map(&:strip).reject(&:blank?).uniq
    end

    def filter_dependencies(dependencies)
      blocked_set = GemVersion.blocked
        .joins(:gem_package)
        .pluck("gem_packages.name", :version, :platform)
        .to_set

      quarantined_set = QuarantinedVersion.active
        .pluck(:name, :version, :platform)
        .to_set

      excluded_set = blocked_set | quarantined_set

      dependencies.reject do |dependency|
        name = dependency["name"] || dependency[:name]
        version = dependency["number"] || dependency[:number] || dependency["version"] || dependency[:version]
        platform = dependency["platform"] || dependency[:platform]
        platform = platform.to_s.presence || "ruby"

        excluded_set.include?([name, version.to_s, platform])
      end
    end

    def refresh_quarantine_state(gem_names)
      gem_names.all? { |gem_name| refresh_gem_quarantine_state(gem_name) }
    end

    def refresh_gem_quarantine_state(gem_name)
      versions = RubygemsClient.fetch_all_versions(gem_name)
      return false unless versions

      recent_versions = versions.filter_map do |version_info|
        quarantine_record_for(gem_name, version_info)
      end

      if recent_versions.any?
        QuarantinedVersion.upsert_all(
          recent_versions,
          unique_by: [:name, :version, :platform]
        )
        ResolverMetadataInvalidator.invalidate!(gem_names: [gem_name])
      end

      true
    end

    def quarantine_record_for(gem_name, version_info)
      published_at = parse_timestamp(version_info["created_at"])
      return unless published_at && published_at > Setting.quarantine_period.ago

      now = Time.current
      {
        name: gem_name,
        version: version_info["number"].to_s,
        platform: version_info["platform"].presence || "ruby",
        first_seen_at: now,
        created_at: now,
        updated_at: now
      }
    end

    def parse_timestamp(value)
      Time.parse(value)
    rescue TypeError, ArgumentError
      nil
    end
  end
end
