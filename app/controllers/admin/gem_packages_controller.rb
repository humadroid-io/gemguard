module Admin
  class GemPackagesController < BaseController
    include Pagy::Method

    before_action :require_specs_available, only: [:approve_version, :block_version]

    def index
      scope = GemPackage.includes(:versions).order(updated_at: :desc)

      if params[:search].present?
        scope = scope.where("name LIKE ?", "%#{params[:search]}%")
      end

      if params[:status].present?
        scope = scope.joins(:versions)
          .where(gem_versions: {status: params[:status]})
          .distinct
      end

      @pagy, @gem_packages = pagy(scope, limit: 25)
    end

    def show
      @gem_package = GemPackage.find(params[:id])
      @versions = @gem_package.versions.order(published_at: :desc)
    end

    def refresh
      @gem_package = GemPackage.find(params[:id])
      service = GemRefreshService.new(@gem_package)

      if service.call
        message = "Gem refreshed from RubyGems"
        message += " (#{service.new_versions_count} new versions)" if service.new_versions_count > 0
        regenerate_specs if service.new_versions_count > 0
        redirect_to admin_gem_package_path(@gem_package), notice: message
      else
        redirect_to admin_gem_package_path(@gem_package), alert: "Refresh failed: #{service.errors.join(", ")}"
      end
    end

    def approve_version
      @gem_package = GemPackage.find(params[:id])
      @version = @gem_package.versions.find(params[:version_id])
      @version.update!(status: :approved)

      # Remove from quarantine so it appears in specs
      QuarantinedVersion.where(
        name: @gem_package.name,
        version: @version.version,
        platform: @version.platform
      ).destroy_all

      regenerate_specs
      redirect_to admin_gem_package_path(@gem_package), notice: "Version #{@version.version} approved"
    end

    def block_version
      @gem_package = GemPackage.find(params[:id])
      @version = @gem_package.versions.find(params[:version_id])
      @version.update!(status: :blocked)

      # Ensure it's in quarantine so it's excluded from specs
      QuarantinedVersion.find_or_create_by!(
        name: @gem_package.name,
        version: @version.version,
        platform: @version.platform
      ) do |qv|
        qv.first_seen_at = Time.current
      end

      regenerate_specs
      redirect_to admin_gem_package_path(@gem_package), notice: "Version #{@version.version} blocked"
    end

    private

    def require_specs_available
      return if SpecsAvailabilityService.available?

      @gem_package = GemPackage.find(params[:id])
      redirect_to admin_gem_package_path(@gem_package),
        alert: "Cannot modify gem status: #{SpecsAvailabilityService.status_message}"
    end

    def regenerate_specs
      # Regenerate all spec files to reflect the change
      %i[all latest prerelease].each do |type|
        RegenerateFilteredSpecsJob.perform_later(type: type)
      end
    end
  end
end
