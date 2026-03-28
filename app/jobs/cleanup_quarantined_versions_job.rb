class CleanupQuarantinedVersionsJob < ApplicationJob
  queue_as :low

  def perform
    deleted_count = 0

    QuarantinedVersion.expired.find_each do |quarantined_version|
      # Use destroy! so the quarantine callbacks regenerate filtered metadata.
      quarantined_version.destroy!
      deleted_count += 1
    end

    if deleted_count > 0
      Rails.logger.info("CleanupQuarantinedVersionsJob: Deleted #{deleted_count} expired quarantine entries")
    end
  end
end
