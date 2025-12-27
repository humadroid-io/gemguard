class CleanupQuarantinedVersionsJob < ApplicationJob
  queue_as :low

  def perform
    deleted_count = QuarantinedVersion.expired.delete_all

    if deleted_count > 0
      Rails.logger.info("CleanupQuarantinedVersionsJob: Deleted #{deleted_count} expired quarantine entries")
    end
  end
end
