module Admin
  class SettingsController < BaseController
    def show
      @settings = {
        quarantine_hours: Setting.quarantine_hours,
        cache_gems: Setting.cache_gems?,
        upstream_source: Setting.upstream_source
      }
    end

    def update
      if params[:quarantine_hours].present?
        Setting.set(:quarantine_hours, params[:quarantine_hours].to_i)
      end

      if params.key?(:cache_gems)
        Setting.set(:cache_gems, params[:cache_gems] == "1")
      end

      if params[:upstream_source].present?
        Setting.set(:upstream_source, params[:upstream_source])
      end

      redirect_to admin_settings_path, notice: "Settings updated successfully."
    end

    def import_baseline
      if Setting.baseline_imported?
        redirect_to admin_settings_path, alert: "Baseline already imported."
        return
      end

      include_prerelease = params[:include_prerelease] == "1"
      ImportSpecsBaselineJob.perform_later(include_prerelease: include_prerelease)
      redirect_to admin_settings_path, notice: "Baseline import started. This may take 2-5 minutes."
    end
  end
end
