module Api
  class DependenciesController < BaseController
    def index
      gem_names = requested_gems
      return head :bad_request if gem_names.empty?

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
  end
end
