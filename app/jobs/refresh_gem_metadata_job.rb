class RefreshGemMetadataJob < ApplicationJob
  queue_as :default

  def perform(gem_names)
    Array(gem_names).uniq.each do |name|
      gem_package = GemPackage.tracked.find_by(name: name)
      next unless gem_package

      service = GemRefreshService.new(gem_package)
      unless service.call
        Rails.logger.warn("RefreshGemMetadataJob: Failed to refresh #{name}: #{service.errors.join(", ")}")
      end
    end
  end
end
