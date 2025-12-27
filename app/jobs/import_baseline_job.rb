# frozen_string_literal: true

class ImportBaselineJob < ApplicationJob
  queue_as :default

  def perform(url: nil)
    return if Setting.baseline_imported?

    url ||= Setting.baseline_url

    Rails.logger.info "Starting baseline import from #{url}"
    count = BaselineService.import_from_url(url)
    Setting.set(:baseline_imported_at, Time.current.iso8601)
    Rails.logger.info "Baseline import complete: #{count} gems imported"

    # Regenerate specs after baseline import
    %i[all latest prerelease].each do |type|
      RegenerateFilteredSpecsJob.perform_later(type: type)
    end
  end
end
