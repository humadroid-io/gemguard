# frozen_string_literal: true

class ImportSpecsBaselineJob < ApplicationJob
  queue_as :default

  # Prevent multiple concurrent imports
  limits_concurrency to: 1, key: ->(*) { "baseline_import" }

  def perform(include_prerelease: false)
    # Skip if already imported (handles race conditions)
    if Setting.baseline_imported?
      Rails.logger.info("ImportSpecsBaselineJob: Baseline already imported, skipping")
      return
    end

    Rails.logger.info("ImportSpecsBaselineJob: Starting specs baseline import")

    count = SpecsBaselineImporter.import(include_prerelease: include_prerelease)

    Rails.logger.info("ImportSpecsBaselineJob: Completed import of #{count} versions")

    # Regenerate filtered specs
    %i[all latest prerelease].each do |type|
      RegenerateFilteredSpecsJob.perform_later(type: type)
    end
  end
end
