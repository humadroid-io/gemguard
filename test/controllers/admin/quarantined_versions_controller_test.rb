require "test_helper"

class Admin::QuarantinedVersionsControllerTest < ActionDispatch::IntegrationTest
  include SpecsTestHelper

  setup do
    setup_test_specs_directory
    stub_specs_paths!
    @quarantined = create(:quarantined_version, name: "test-gem", version: "1.0.0")

    # Create raw specs to enable approve/block actions
    @specs_path = SpecsTestHelper::TEST_RAW_SPECS_PATH
    File.write(@specs_path.join("specs.4.8.gz"), "test")
  end

  teardown do
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "index returns success" do
    get admin_quarantined_versions_path
    assert_response :success
  end

  test "index displays quarantined versions" do
    get admin_quarantined_versions_path

    assert_select "td", text: /test-gem/
    assert_select "td", text: "1.0.0"
  end

  test "index filters by search" do
    create(:quarantined_version, name: "other-gem", version: "2.0.0")

    get admin_quarantined_versions_path, params: {search: "test-gem"}

    assert_response :success
    assert_select "td", text: /test-gem/
    assert_select "td", text: /other-gem/, count: 0
  end

  test "index filters by active status" do
    create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    get admin_quarantined_versions_path, params: {status: "active"}

    assert_response :success
    assert_select "td", text: /test-gem/
    assert_select "td", text: /old-gem/, count: 0
  end

  test "index filters by expired status" do
    create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    get admin_quarantined_versions_path, params: {status: "expired"}

    assert_response :success
    assert_select "td", text: /old-gem/
    assert_select "td", text: /test-gem/, count: 0
  end

  test "index filters by used or installed gems only" do
    create(:gem_package, name: "test-gem")
    create(:quarantined_version, name: "unused-gem", version: "2.0.0")

    get admin_quarantined_versions_path, params: {usage: "used"}

    assert_response :success
    assert_select "td", text: /test-gem/
    assert_select "td", text: /unused-gem/, count: 0
  end

  test "index shows clear filters link when usage filter is active" do
    get admin_quarantined_versions_path, params: {usage: "used"}

    assert_response :success
    assert_select "a", text: "Clear"
  end

  test "index shows stats" do
    create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    get admin_quarantined_versions_path

    assert_select ".stat-value", text: "1" # Active count
  end

  test "approve creates approved GemVersion and removes from quarantine" do
    assert_difference "GemVersion.count", 1 do
      assert_difference "QuarantinedVersion.count", -1 do
        post approve_admin_quarantined_version_path(@quarantined)
      end
    end

    assert_redirected_to admin_quarantined_versions_path

    gem_version = GemVersion.last
    assert_equal "test-gem", gem_version.gem_package.name
    assert_equal "1.0.0", gem_version.version
    assert gem_version.approved?
  end

  test "approve enqueues spec regeneration" do
    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      post approve_admin_quarantined_version_path(@quarantined)
    end
  end

  test "block creates blocked GemVersion and keeps in quarantine" do
    assert_difference "GemVersion.count", 1 do
      assert_no_difference "QuarantinedVersion.count" do
        post block_admin_quarantined_version_path(@quarantined)
      end
    end

    assert_redirected_to admin_quarantined_versions_path

    gem_version = GemVersion.last
    assert_equal "test-gem", gem_version.gem_package.name
    assert gem_version.blocked?
  end

  test "block enqueues spec regeneration" do
    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      post block_admin_quarantined_version_path(@quarantined)
    end
  end

  test "destroy removes from quarantine" do
    assert_difference "QuarantinedVersion.count", -1 do
      delete admin_quarantined_version_path(@quarantined)
    end

    assert_redirected_to admin_quarantined_versions_path
  end

  test "destroy enqueues spec regeneration" do
    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      delete admin_quarantined_version_path(@quarantined)
    end
  end

  test "approve_all_expired approves only expired versions" do
    active = @quarantined # This is active (created recently)
    create(:quarantined_version, :expired, name: "old-gem-1", version: "1.0.0")
    create(:quarantined_version, :expired, name: "old-gem-2", version: "1.0.0")

    assert_difference "GemVersion.count", 2 do
      assert_difference "QuarantinedVersion.count", -2 do
        post approve_all_expired_admin_quarantined_versions_path
      end
    end

    assert_redirected_to admin_quarantined_versions_path

    # Active version should still exist
    assert QuarantinedVersion.exists?(id: active.id)

    # Expired versions should be approved
    assert GemVersion.exists?(gem_package: GemPackage.find_by(name: "old-gem-1"))
    assert GemVersion.exists?(gem_package: GemPackage.find_by(name: "old-gem-2"))
  end

  test "approve_all_expired enqueues spec regeneration" do
    create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      post approve_all_expired_admin_quarantined_versions_path
    end
  end

  test "index paginates results" do
    55.times { |i| create(:quarantined_version, name: "gem-#{i}", version: "1.0.0") }

    get admin_quarantined_versions_path

    assert_response :success
    # Should show pagination when more than 50 results
    assert_select "nav"
  end

  test "approve blocked when specs not available" do
    FileUtils.rm_rf(@specs_path)

    post approve_admin_quarantined_version_path(@quarantined)

    assert_redirected_to admin_quarantined_versions_path
    assert_match(/Cannot modify gem status/, flash[:alert])
    assert QuarantinedVersion.exists?(id: @quarantined.id)
  end

  test "block blocked when specs not available" do
    FileUtils.rm_rf(@specs_path)

    post block_admin_quarantined_version_path(@quarantined)

    assert_redirected_to admin_quarantined_versions_path
    assert_match(/Cannot modify gem status/, flash[:alert])
  end

  test "destroy blocked when specs not available" do
    FileUtils.rm_rf(@specs_path)

    delete admin_quarantined_version_path(@quarantined)

    assert_redirected_to admin_quarantined_versions_path
    assert_match(/Cannot modify gem status/, flash[:alert])
    assert QuarantinedVersion.exists?(id: @quarantined.id)
  end

  test "approve_all_expired blocked when specs not available" do
    FileUtils.rm_rf(@specs_path)
    create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    post approve_all_expired_admin_quarantined_versions_path

    assert_redirected_to admin_quarantined_versions_path
    assert_match(/Cannot modify gem status/, flash[:alert])
  end

  test "index displays warning when specs not available" do
    FileUtils.rm_rf(@specs_path)

    get admin_quarantined_versions_path

    assert_select ".alert-warning", text: /Specs not synced/
  end

  test "index hides action buttons when specs not available" do
    FileUtils.rm_rf(@specs_path)

    get admin_quarantined_versions_path

    assert_select "button", text: "Approve", count: 0
    assert_select "button", text: "Block", count: 0
    assert_select "span", text: "Sync specs first"
  end

  test "index hides approve all expired button when specs not available" do
    FileUtils.rm_rf(@specs_path)
    create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    get admin_quarantined_versions_path

    assert_select "button", text: "Approve All Expired", count: 0
  end
end
