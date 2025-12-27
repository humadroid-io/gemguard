module Admin
  class DashboardController < BaseController
    def index
      @stats = {
        total_gems: GemPackage.count,
        total_versions: GemVersion.count,
        quarantined: GemVersion.quarantined.count,
        approved: GemVersion.approved.count,
        blocked: GemVersion.blocked.count,
        recent_downloads: AuditLog.downloads.where("requested_at > ?", 24.hours.ago).count
      }
    end
  end
end
