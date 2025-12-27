# frozen_string_literal: true

class ImportSpecsBaselineJob < ApplicationJob
  queue_as :default

  def perform(include_prerelease: false)
    Rails.logger.info("ImportSpecsBaselineJob: Starting specs baseline import")

    count = SpecsBaselineImporter.import(include_prerelease: include_prerelease)

    Rails.logger.info("ImportSpecsBaselineJob: Completed import of #{count} versions")

    # Regenerate filtered specs
    %i[all latest prerelease].each do |type|
      RegenerateFilteredSpecsJob.perform_later(type: type)
    end
  end
end
