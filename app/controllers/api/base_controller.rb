module Api
  class BaseController < ActionController::API
    before_action :ensure_bootstrapped
    before_action :log_request

    private

    def ensure_bootstrapped
      ManagedApp.ensure_default!
      return if Setting.baseline_imported?

      # Queue baseline import (only once - job deduplication prevents multiple runs)
      ImportSpecsBaselineJob.perform_later(include_prerelease: true)
    end

    def log_request
      # Subclasses override to log specific actions
    end

    def storage_path
      Rails.root.join("storage")
    end

    def specs_path
      storage_path.join("specs")
    end

    def gems_path
      storage_path.join("gems")
    end

    def send_cached_file(path, content_type:)
      if File.exist?(path)
        send_file path, type: content_type, disposition: "inline"
      else
        head :not_found
      end
    end
  end
end
