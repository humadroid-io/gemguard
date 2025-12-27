module Admin
  class QuarantineRulesController < BaseController
    before_action :set_quarantine_rule, only: [:edit, :update, :destroy]

    def index
      @quarantine_rules = QuarantineRule.includes(:gem_package).order(created_at: :desc)
    end

    def new
      @quarantine_rule = QuarantineRule.new
      @gem_packages = GemPackage.order(:name)
    end

    def create
      @quarantine_rule = QuarantineRule.new(quarantine_rule_params)

      if @quarantine_rule.save
        redirect_to admin_quarantine_rules_path, notice: "Quarantine rule created successfully."
      else
        @gem_packages = GemPackage.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @gem_packages = GemPackage.order(:name)
    end

    def update
      if @quarantine_rule.update(quarantine_rule_params)
        redirect_to admin_quarantine_rules_path, notice: "Quarantine rule updated successfully."
      else
        @gem_packages = GemPackage.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @quarantine_rule.destroy
      redirect_to admin_quarantine_rules_path, notice: "Quarantine rule deleted."
    end

    private

    def set_quarantine_rule
      @quarantine_rule = QuarantineRule.find(params[:id])
    end

    def quarantine_rule_params
      params.require(:quarantine_rule).permit(:gem_package_id, :rule_type, :value, :enabled, :description)
    end
  end
end
