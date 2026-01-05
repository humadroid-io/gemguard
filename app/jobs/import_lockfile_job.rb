class ImportLockfileJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default

  # Refresh all gems that were imported from a lockfile
  # Uses GemRefreshService to fetch metadata and detect newer versions
  #
  # This job is continuable - if interrupted, it resumes from the last processed gem
  def perform(gem_names)
    step :refresh_gems do |step|
      refresh_all_gems(gem_names, step)
    end

    step :regenerate_specs do
      regenerate_filtered_specs
    end
  end

  private

  def refresh_all_gems(gem_names, step)
    Rails.logger.info("ImportLockfileJob: Refreshing #{gem_names.size} gems")

    refreshed = 0
    quarantined = 0

    # Resume from cursor position (index of last processed gem)
    start_index = step.cursor || 0

    gem_names[start_index..].each_with_index do |name, offset|
      current_index = start_index + offset

      result = refresh_gem(name)
      if result
        refreshed += 1
        quarantined += result
      end

      # Save progress after each gem - allows resumption if interrupted
      step.advance! from: current_index + 1
    end

    Rails.logger.info("ImportLockfileJob: Refreshed #{refreshed} gems, found #{quarantined} versions to quarantine")
  end

  def refresh_gem(name)
    gem_package = GemPackage.find_by(name: name)
    return nil unless gem_package

    service = GemRefreshService.new(gem_package)
    if service.call
      service.new_versions_count
    else
      Rails.logger.warn("ImportLockfileJob: Failed to refresh #{name}: #{service.errors.join(", ")}")
      nil
    end
  end

  def regenerate_filtered_specs
    # Check if any gems were quarantined by looking at recently created QuarantinedVersions
    recent_quarantined = QuarantinedVersion.where("created_at > ?", 1.hour.ago).count

    if recent_quarantined > 0
      Rails.logger.info("ImportLockfileJob: Regenerating filtered specs")
      RegenerateFilteredSpecsJob.perform_later(type: :all)
      RegenerateFilteredSpecsJob.perform_later(type: :latest)
    else
      Rails.logger.info("ImportLockfileJob: No new quarantined versions, skipping specs regeneration")
    end
  end
end
