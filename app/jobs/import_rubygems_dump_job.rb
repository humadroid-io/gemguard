# frozen_string_literal: true

class ImportRubygemsDumpJob < ApplicationJob
  queue_as :default

  def perform
    return if Setting.baseline_imported?

    Rails.logger.info "Starting RubyGems dump import job"
    RubygemsDumpImporter.import
    Rails.logger.info "RubyGems dump import complete"

    # Regenerate specs after import
    %i[all latest prerelease].each do |type|
      RegenerateFilteredSpecsJob.perform_later(type: type)
    end
  end
end
