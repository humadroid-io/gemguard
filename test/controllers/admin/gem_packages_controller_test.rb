require "test_helper"
require "webmock/minitest"

class Admin::GemPackagesControllerTest < ActionDispatch::IntegrationTest
  include SpecsTestHelper

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    setup_test_specs_directory
    stub_specs_paths!
    @gem_package = create(:gem_package, name: "rails")
    @version = create(:gem_version, :approved, gem_package: @gem_package, version: "7.0.0")

    # Create raw specs to enable approve/block actions
    @specs_path = SpecsTestHelper::TEST_RAW_SPECS_PATH
    File.write(@specs_path.join("specs.4.8.gz"), "test")
  end

  teardown do
    WebMock.allow_net_connect!
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "index returns success" do
    get admin_gem_packages_path
    assert_response :success
  end

  test "index displays gem packages" do
    get admin_gem_packages_path
    assert_select "td", text: /rails/
  end

  test "index filters by search query" do
    create(:gem_package, name: "nokogiri")

    get admin_gem_packages_path, params: {search: "rails"}

    assert_response :success
    assert_select "td", text: /rails/
    assert_select "td", text: /nokogiri/, count: 0
  end

  test "index filters by status" do
    quarantined_pkg = create(:gem_package, name: "risky-gem")
    create(:gem_version, :quarantined, gem_package: quarantined_pkg)

    get admin_gem_packages_path, params: {status: "quarantined"}

    assert_response :success
    assert_select "td", text: /risky-gem/
  end

  test "show returns success" do
    get admin_gem_package_path(@gem_package)
    assert_response :success
  end

  test "show displays gem package details" do
    get admin_gem_package_path(@gem_package)

    assert_select "h1", text: /rails/
    assert_select "td", text: "7.0.0"
  end

  test "show displays version status" do
    get admin_gem_package_path(@gem_package)

    assert_select ".badge", text: /Approved/
  end

  test "approve_version changes status to approved" do
    quarantined = create(:gem_version, :quarantined, gem_package: @gem_package, version: "7.1.0")

    post approve_version_admin_gem_package_path(@gem_package, version_id: quarantined.id)

    assert_redirected_to admin_gem_package_path(@gem_package)
    assert quarantined.reload.approved?
  end

  test "approve_version removes from QuarantinedVersion" do
    # GemVersion callback creates QuarantinedVersion automatically when status is :quarantined
    quarantined = create(:gem_version, :quarantined, gem_package: @gem_package, version: "7.1.0")

    assert QuarantinedVersion.exists?(name: @gem_package.name, version: "7.1.0")

    post approve_version_admin_gem_package_path(@gem_package, version_id: quarantined.id)

    assert_not QuarantinedVersion.exists?(name: @gem_package.name, version: "7.1.0")
  end

  test "approve_version enqueues spec regeneration jobs" do
    quarantined = create(:gem_version, :quarantined, gem_package: @gem_package, version: "7.1.0")

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      post approve_version_admin_gem_package_path(@gem_package, version_id: quarantined.id)
    end
  end

  test "block_version changes status to blocked" do
    post block_version_admin_gem_package_path(@gem_package, version_id: @version.id)

    assert_redirected_to admin_gem_package_path(@gem_package)
    assert @version.reload.blocked?
  end

  test "block_version creates QuarantinedVersion entry" do
    assert_not QuarantinedVersion.exists?(name: @gem_package.name, version: @version.version)

    post block_version_admin_gem_package_path(@gem_package, version_id: @version.id)

    assert QuarantinedVersion.exists?(name: @gem_package.name, version: @version.version)
  end

  test "block_version enqueues spec regeneration jobs" do
    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      post block_version_admin_gem_package_path(@gem_package, version_id: @version.id)
    end
  end

  test "index paginates results" do
    30.times { |i| create(:gem_package, name: "gem-#{i}") }

    get admin_gem_packages_path

    assert_response :success
    # Should show pagination when more than 25 results
    assert_select "nav.pagy" # pagy nav element
  end

  test "refresh updates gem info from RubyGems" do
    stub_gem_info("rails", info: "Updated info", homepage_uri: "https://new-url.com", downloads: 999)
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    post refresh_admin_gem_package_path(@gem_package)

    assert_redirected_to admin_gem_package_path(@gem_package)
    assert_match(/refreshed/, flash[:notice])

    @gem_package.reload
    assert_equal "Updated info", @gem_package.info
  end

  test "refresh creates new versions" do
    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_difference "GemVersion.count", 1 do
      post refresh_admin_gem_package_path(@gem_package)
    end

    assert_match(/1 new versions/, flash[:notice])
  end

  test "refresh enqueues spec regeneration when new versions found" do
    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.2.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      post refresh_admin_gem_package_path(@gem_package)
    end
  end

  test "refresh does not regenerate specs when no new versions" do
    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_no_enqueued_jobs only: RegenerateFilteredSpecsJob do
      post refresh_admin_gem_package_path(@gem_package)
    end
  end

  test "refresh shows error on API failure" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/rails.json")
      .to_return(status: 500)
    stub_versions("rails", [])

    post refresh_admin_gem_package_path(@gem_package)

    assert_redirected_to admin_gem_package_path(@gem_package)
    assert_match(/failed/, flash[:alert])
  end

  test "show displays refresh button" do
    get admin_gem_package_path(@gem_package)

    assert_select "form[action=?]", refresh_admin_gem_package_path(@gem_package)
    assert_select "button", text: /Refresh from RubyGems/
  end

  test "show displays tracked status for tracked gem" do
    @gem_package.update!(tracked_at: 1.week.ago)

    get admin_gem_package_path(@gem_package)

    assert_select ".badge", text: "Tracked"
  end

  test "show displays not tracked status for untracked gem" do
    @gem_package.update!(tracked_at: nil)

    get admin_gem_package_path(@gem_package)

    assert_select ".badge", text: "Not tracked"
  end

  test "approve_version blocked when specs not available" do
    FileUtils.rm_rf(@specs_path)
    quarantined = create(:gem_version, :quarantined, gem_package: @gem_package, version: "7.1.0")

    post approve_version_admin_gem_package_path(@gem_package, version_id: quarantined.id)

    assert_redirected_to admin_gem_package_path(@gem_package)
    assert_match(/Cannot modify gem status/, flash[:alert])
    assert quarantined.reload.quarantined?
  end

  test "block_version blocked when specs not available" do
    FileUtils.rm_rf(@specs_path)

    post block_version_admin_gem_package_path(@gem_package, version_id: @version.id)

    assert_redirected_to admin_gem_package_path(@gem_package)
    assert_match(/Cannot modify gem status/, flash[:alert])
    assert @version.reload.approved?
  end

  test "show displays warning when specs not available" do
    FileUtils.rm_rf(@specs_path)

    get admin_gem_package_path(@gem_package)

    assert_select ".alert-warning", text: /Specs not synced/
  end

  test "show hides approve/block buttons when specs not available" do
    FileUtils.rm_rf(@specs_path)
    create(:gem_version, :quarantined, gem_package: @gem_package, version: "7.1.0")

    get admin_gem_package_path(@gem_package)

    assert_select "button", text: "Approve", count: 0
    assert_select "button", text: "Block", count: 0
    assert_select "span", text: "Sync specs first"
  end

  private

  def stub_gem_info(name, info: "A gem", homepage_uri: "https://example.com", downloads: 1000)
    stub_request(:get, "https://rubygems.org/api/v1/gems/#{name}.json")
      .to_return(status: 200, body: {
        "name" => name,
        "info" => info,
        "homepage_uri" => homepage_uri,
        "downloads" => downloads
      }.to_json)
  end

  def stub_versions(name, versions)
    stub_request(:get, "https://rubygems.org/api/v1/versions/#{name}.json")
      .to_return(status: 200, body: versions.to_json)
  end
end
