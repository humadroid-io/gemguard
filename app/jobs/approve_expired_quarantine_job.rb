class ApproveExpiredQuarantineJob < ApplicationJob
  queue_as :default

  def perform
    expired_count = 0

    GemVersion.quarantined.find_each do |gem_version|
      # Skip if still actively quarantined
      next if gem_version.actively_quarantined?

      gem_version.update!(status: :approved)
      # Auto-approval also has to clear the active quarantine row so filtered
      # specs and compact index metadata expose the version again right away.
      QuarantinedVersion.where(
        name: gem_version.gem_name,
        version: gem_version.version,
        platform: gem_version.platform
      ).destroy_all
      expired_count += 1
    end

    Rails.logger.info("ApproveExpiredQuarantineJob: Approved #{expired_count} gems past quarantine period") if expired_count > 0
  end
end
