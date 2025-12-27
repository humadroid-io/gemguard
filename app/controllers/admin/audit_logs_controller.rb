module Admin
  class AuditLogsController < BaseController
    include Pagy::Method

    def index
      scope = AuditLog.order(requested_at: :desc)

      if params[:gem_name].present?
        scope = scope.where("gem_name LIKE ?", "%#{params[:gem_name]}%")
      end

      if params[:action_type].present?
        scope = scope.where(action: params[:action_type])
      end

      if params[:date_from].present?
        scope = scope.where("requested_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
      end

      if params[:date_to].present?
        scope = scope.where("requested_at <= ?", Date.parse(params[:date_to]).end_of_day)
      end

      @pagy, @audit_logs = pagy(scope, limit: 50)
    end

    def export
      @audit_logs = AuditLog.order(requested_at: :desc)

      if params[:date_from].present?
        @audit_logs = @audit_logs.where("requested_at >= ?", Date.parse(params[:date_from]).beginning_of_day)
      end

      if params[:date_to].present?
        @audit_logs = @audit_logs.where("requested_at <= ?", Date.parse(params[:date_to]).end_of_day)
      end

      respond_to do |format|
        format.csv do
          headers["Content-Disposition"] = "attachment; filename=audit_logs_#{Date.current}.csv"
          headers["Content-Type"] = "text/csv"
        end
      end
    end
  end
end
