require "test_helper"

class Admin::AppsControllerTest < ActionDispatch::IntegrationTest
  LOCKFILE = <<~LOCKFILE
    GEM
      remote: https://rubygems.org/
      specs:
        rack (3.1.0)
        rails (7.1.0)
          rack (>= 2.2.4)

    DEPENDENCIES
      rails
  LOCKFILE

  test "index returns success" do
    create(:managed_app, name: "Storefront")

    get admin_apps_path

    assert_response :success
    assert_select "h1", text: "Apps"
    assert_select "td", text: /Storefront/
  end

  test "show displays dependency tree" do
    app = create(:managed_app, name: "Storefront")
    rails_package = create(:gem_package, name: "rails")
    rack_package = create(:gem_package, name: "rack")
    rails_version = create(:gem_version, :approved, gem_package: rails_package, version: "7.1.0")
    rack_version = create(:gem_version, :approved, gem_package: rack_package, version: "3.1.0")

    create(:app_gem_version, managed_app: app, gem_version: rails_version, direct: true)
    create(:app_gem_version, managed_app: app, gem_version: rack_version, direct: false)
    create(:app_dependency_edge, managed_app: app, parent_gem_version: rails_version, child_gem_version: rack_version, requirement: ">= 2.2.4")

    get admin_app_path(app)

    assert_response :success
    assert_select "h1", text: "Storefront"
    assert_select "span", text: /rails/
    assert_select "span", text: /rack/
  end

  test "create persists a new app" do
    ManagedApp.ensure_default!

    assert_difference "ManagedApp.count", 1 do
      post admin_apps_path, params: {
        managed_app: {
          name: "Storefront",
          slug: "storefront",
          description: "Shop app",
          quarantine_hours: "24",
          cache_gems_override: "true",
          upstream_source: "https://rubygems.org"
        }
      }
    end

    app = ManagedApp.last
    assert_redirected_to admin_app_path(app)
    assert_equal 24, app.quarantine_hours
    assert_equal true, app.cache_gems
  end

  test "import_lockfile assigns gems to app" do
    app = create(:managed_app, name: "Storefront")
    lockfile = Tempfile.new(["Gemfile", ".lock"])
    lockfile.write(LOCKFILE)
    lockfile.rewind

    assert_difference "GemPackage.count", 2 do
      assert_difference "AppGemVersion.count", 2 do
        assert_difference "AppDependencyEdge.count", 1 do
          post import_lockfile_admin_app_path(app), params: {
            lockfile: Rack::Test::UploadedFile.new(lockfile.path, "text/plain", original_filename: "Gemfile.lock")
          }
        end
      end
    end

    assert_redirected_to admin_app_path(app)
    assert app.gem_versions.joins(:gem_package).exists?(gem_packages: {name: "rails"})
  ensure
    lockfile.close!
  end
end
