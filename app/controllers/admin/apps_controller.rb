module Admin
  class AppsController < BaseController
    def index
      @apps = ManagedApp.includes(app_gem_versions: {gem_version: :gem_package}).recently_updated
    end

    def show
      @app = ManagedApp.find(params[:id])
      @direct_gem_versions = @app.direct_gem_versions.includes(:gem_package).order("gem_packages.name")
      @app_gem_versions = @app.app_gem_versions.includes(gem_version: :gem_package).order("gem_packages.name")
      @dependency_tree = build_dependency_tree(@app)
    end

    def new
      @app = ManagedApp.new
    end

    def create
      @app = ManagedApp.new(app_params)

      if @app.save
        redirect_to admin_app_path(@app), notice: "App created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @app = ManagedApp.find(params[:id])
    end

    def update
      @app = ManagedApp.find(params[:id])

      if @app.update(app_params)
        redirect_to admin_app_path(@app), notice: "App updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @app = ManagedApp.find(params[:id])
      @app.destroy
      redirect_to admin_apps_path, notice: "App deleted."
    end

    def import_lockfile
      @app = ManagedApp.find(params[:id])

      unless params[:lockfile].present?
        redirect_to admin_app_path(@app), alert: "Please select a Gemfile.lock file."
        return
      end

      result = LockfileImporter.import(params[:lockfile].read, managed_app: @app)
      message = "Imported #{result.imported} new gem versions for #{@app.name}. "
      message += "Tracked #{result.app_gems} resolved app gems and queued #{result.queued} gems for metadata refresh."

      redirect_to admin_app_path(@app), notice: message
    end

    private

    def app_params
      params.require(:managed_app).permit(:name, :description, :slug, :quarantine_hours, :upstream_source).merge(
        cache_gems: parse_cache_gems_override
      )
    end

    def parse_cache_gems_override
      case params.dig(:managed_app, :cache_gems_override)
      when "true" then true
      when "false" then false
      else nil
      end
    end

    def build_dependency_tree(app)
      edges = app.app_dependency_edges.includes(parent_gem_version: :gem_package, child_gem_version: :gem_package)
      children_by_parent = edges.group_by(&:parent_gem_version_id)
      visited = Set.new

      app.direct_gem_versions.includes(:gem_package).order("gem_packages.name").map do |gem_version|
        build_node(gem_version, children_by_parent, visited)
      end.compact
    end

    def build_node(gem_version, children_by_parent, visited)
      key = [gem_version.id]
      return if visited.include?(key)

      visited << key

      {
        gem_version: gem_version,
        children: Array(children_by_parent[gem_version.id]).sort_by { |edge| edge.child_gem_version.gem_name }.map do |edge|
          child_node = build_node(edge.child_gem_version, children_by_parent, visited)
          child_node&.merge(requirement: edge.requirement)
        end.compact
      }
    end
  end
end
