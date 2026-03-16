require "test_helper"

class LockfileImporterTest < ActiveSupport::TestCase
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

  test "imports resolved gems into a managed app with dependency tree" do
    app = create(:managed_app, name: "Storefront")

    assert_difference "GemPackage.count", 2 do
      assert_difference "GemVersion.count", 2 do
        assert_difference "AppGemVersion.count", 2 do
          assert_difference "AppDependencyEdge.count", 1 do
            result = LockfileImporter.import(LOCKFILE, managed_app: app)

            assert_equal 2, result.app_gems
            assert_equal 2, result.queued
          end
        end
      end
    end

    rails_version = GemVersion.joins(:gem_package).find_by(gem_packages: {name: "rails"})
    rack_version = GemVersion.joins(:gem_package).find_by(gem_packages: {name: "rack"})

    assert app.app_gem_versions.exists?(gem_version: rails_version, direct: true)
    assert app.app_gem_versions.exists?(gem_version: rack_version, direct: false)
    assert app.app_dependency_edges.exists?(parent_gem_version: rails_version, child_gem_version: rack_version)
  end

  test "reimport replaces app membership with current lockfile" do
    app = create(:managed_app, name: "Storefront")
    LockfileImporter.import(LOCKFILE, managed_app: app)

    new_lockfile = <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          nokogiri (1.18.0)

      DEPENDENCIES
        nokogiri
    LOCKFILE

    LockfileImporter.import(new_lockfile, managed_app: app)

    gem_names = app.gem_versions.joins(:gem_package).pluck("gem_packages.name")
    assert_equal ["nokogiri"], gem_names
    assert_equal 0, app.app_dependency_edges.count
  end
end
