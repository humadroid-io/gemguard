module Admin
  class QuarantinedVersionsController < BaseController
    include Pagy::Method

    before_action :require_specs_available, only: [:approve, :block, :destroy, :approve_all_expired]

    def index
      scope = QuarantinedVersion.order(first_seen_at: :desc)

      if params[:search].present?
        scope = scope.where("name LIKE ?", "%#{params[:search]}%")
      end

      if params[:status].present?
        case params[:status]
        when "active"
          scope = scope.active
        when "expired"
          scope = scope.expired
        end
      end

      @pagy, @quarantined_versions = pagy(scope, limit: 50)
    end

    def approve
      @quarantined_version = QuarantinedVersion.find(params[:id])

      # Create or update GemVersion as approved
      gem_package = GemPackage.find_or_create_by!(name: @quarantined_version.name)
      gem_version = gem_package.versions.find_or_initialize_by(
        version: @quarantined_version.version,
        platform: @quarantined_version.platform
      )
      gem_version.status = :approved
      gem_version.first_seen_at ||= @quarantined_version.first_seen_at
      gem_version.save!

      # Remove from quarantine (callback triggers specs regeneration)
      @quarantined_version.destroy

      redirect_to admin_quarantined_versions_path, notice: "#{@quarantined_version.name} #{@quarantined_version.version} approved"
    end

    def block
      @quarantined_version = QuarantinedVersion.find(params[:id])

      # Create or update GemVersion as blocked
      gem_package = GemPackage.find_or_create_by!(name: @quarantined_version.name)
      gem_version = gem_package.versions.find_or_initialize_by(
        version: @quarantined_version.version,
        platform: @quarantined_version.platform
      )
      gem_version.status = :blocked
      gem_version.first_seen_at ||= @quarantined_version.first_seen_at
      gem_version.save!

      # Keep in quarantine - specs regeneration needed for blocked status
      regenerate_specs
      redirect_to admin_quarantined_versions_path, notice: "#{@quarantined_version.name} #{@quarantined_version.version} blocked"
    end

    def destroy
      @quarantined_version = QuarantinedVersion.find(params[:id])
      # Callback triggers specs regeneration
      @quarantined_version.destroy

      redirect_to admin_quarantined_versions_path, notice: "#{@quarantined_version.name} #{@quarantined_version.version} removed from quarantine"
    end

    def approve_all_expired
      expired = QuarantinedVersion.expired

      expired.find_each do |qv|
        gem_package = GemPackage.find_or_create_by!(name: qv.name)
        gem_version = gem_package.versions.find_or_initialize_by(
          version: qv.version,
          platform: qv.platform
        )
        gem_version.status = :approved
        gem_version.first_seen_at ||= qv.first_seen_at
        gem_version.save!
      end

      count = expired.count
      # Each destroy triggers callback; concurrency limits prevent duplicate runs
      expired.destroy_all

      redirect_to admin_quarantined_versions_path, notice: "#{count} expired versions approved"
    end

    private

    def require_specs_available
      return if SpecsAvailabilityService.available?

      redirect_to admin_quarantined_versions_path,
        alert: "Cannot modify gem status: #{SpecsAvailabilityService.status_message}"
    end

    def regenerate_specs
      %i[all latest prerelease].each do |type|
        RegenerateFilteredSpecsJob.perform_later(type: type)
      end
    end
  end
end
