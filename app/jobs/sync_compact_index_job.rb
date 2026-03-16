class SyncCompactIndexJob < ApplicationJob
  queue_as :default

  # Limit concurrency to avoid multiple syncs of the same type
  limits_concurrency to: 1, key: ->(options = {}) { options[:type] || options["type"] || :versions }

  def perform(type: :versions, regenerate_only: false)
    case type.to_sym
    when :versions
      if regenerate_only
        CompactIndexService.regenerate_versions
      else
        CompactIndexService.sync_versions
      end
    when :names
      CompactIndexService.sync_names
    else
      Rails.logger.warn("Unknown compact index sync type: #{type}")
    end
  end
end
