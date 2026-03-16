module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :check_bootstrap_status

    private

    def check_bootstrap_status
      ManagedApp.ensure_default!
      return if Setting.baseline_imported?

      # Queue baseline import if not already running
      ImportSpecsBaselineJob.perform_later(include_prerelease: true)

      # Set flash to inform admin
      flash.now[:warning] = "GemGuard is bootstrapping - importing specs baseline from RubyGems.org. This may take a few minutes."
    end
  end
end
