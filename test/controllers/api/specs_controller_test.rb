require "test_helper"
require "webmock/minitest"

class Api::SpecsControllerTest < ActionDispatch::IntegrationTest
  include SpecsTestHelper

  # Disable parallelization due to file system dependencies
  parallelize(workers: 1)

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    setup_test_specs_directory
    stub_specs_paths!
    @specs_path = SpecsTestHelper::TEST_SPECS_PATH
    @raw_specs_path = SpecsTestHelper::TEST_RAW_SPECS_PATH

    # Stub rubygems.org requests for when sync is triggered
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", Gem::Version.new("7.0.0"), "ruby"]]))
    stub_request(:get, "https://rubygems.org/latest_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", Gem::Version.new("7.0.0"), "ruby"]]))
    stub_request(:get, "https://rubygems.org/prerelease_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]]))
  end

  teardown do
    WebMock.allow_net_connect!
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "index returns specs file when cached" do
    create_specs_file("specs.4.8.gz")

    get "/specs.4.8.gz"

    assert_response :success
    assert_equal "application/x-gzip", response.content_type
  end

  test "index proxies from upstream when specs file missing" do
    get "/specs.4.8.gz"

    assert_response :success
    assert File.exist?(@specs_path.join("specs.4.8.gz"))
  end

  test "index returns bad gateway when upstream fails" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 500)

    get "/specs.4.8.gz"

    assert_response :bad_gateway
  end

  test "index creates audit log" do
    create_specs_file("specs.4.8.gz")

    assert_difference "AuditLog.count", 1 do
      get "/specs.4.8.gz"
    end

    log = AuditLog.last
    assert_equal "specs.4.8.gz", log.gem_name
    assert_equal "spec_request", log.action
  end

  test "latest returns latest_specs file" do
    create_specs_file("latest_specs.4.8.gz")

    get "/latest_specs.4.8.gz"

    assert_response :success
  end

  test "prerelease returns prerelease_specs file" do
    create_specs_file("prerelease_specs.4.8.gz")

    get "/prerelease_specs.4.8.gz"

    assert_response :success
  end

  test "filter_specs passes through unknown gems" do
    # Create an approved gem version
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, :approved, gem_package: gem_package, version: "7.0.0", platform: "ruby")

    upstream_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["unknown-gem", Gem::Version.new("1.0.0"), "ruby"]
    ]

    controller = Api::SpecsController.new
    filtered_data = controller.send(:filter_specs, gzipped_specs(upstream_specs))
    specs = parse_gzipped_specs(filtered_data)
    gem_names_versions = specs.map { |n, v, _| [n, v.to_s] }

    assert_includes gem_names_versions, ["rails", "7.0.0"], "Approved version should be included"
    assert_includes gem_names_versions, ["unknown-gem", "1.0.0"], "Unknown gems pass through (tracked on download)"
  end

  test "filter_specs excludes active quarantine versions" do
    # Create an active quarantine entry
    create(:quarantined_version, name: "quarantined-gem", version: "1.0.0", platform: "ruby")

    upstream_specs = [
      ["quarantined-gem", Gem::Version.new("1.0.0"), "ruby"],
      ["unknown-gem", Gem::Version.new("1.0.0"), "ruby"]
    ]

    controller = Api::SpecsController.new
    filtered_data = controller.send(:filter_specs, gzipped_specs(upstream_specs))
    specs = parse_gzipped_specs(filtered_data)
    gem_names_versions = specs.map { |n, v, _| [n, v.to_s] }

    assert_not_includes gem_names_versions, ["quarantined-gem", "1.0.0"], "Active quarantine should be excluded"
    assert_includes gem_names_versions, ["unknown-gem", "1.0.0"], "Unknown gems pass through"
  end

  test "filter_specs excludes blocked versions" do
    # Create a blocked status
    gem_package = create(:gem_package, name: "malicious-gem")
    create(:gem_version, :blocked, gem_package: gem_package, version: "1.0.0", platform: "ruby")

    upstream_specs = [
      ["malicious-gem", Gem::Version.new("1.0.0"), "ruby"],
      ["safe-gem", Gem::Version.new("2.0.0"), "ruby"]
    ]

    controller = Api::SpecsController.new
    filtered_data = controller.send(:filter_specs, gzipped_specs(upstream_specs))
    specs = parse_gzipped_specs(filtered_data)
    gem_names_versions = specs.map { |n, v, _| [n, v.to_s] }

    assert_not_includes gem_names_versions, ["malicious-gem", "1.0.0"], "Blocked version should be excluded"
    assert_includes gem_names_versions, ["safe-gem", "2.0.0"], "Unknown gems pass through"
  end

  test "filter_specs passes through unknown gems - lazy tracking on download" do
    # No gems in database - unknown gems pass through
    # They will be tracked when actually downloaded
    upstream_specs = [
      ["new-gem", Gem::Version.new("1.0.0"), "ruby"]
    ]

    controller = Api::SpecsController.new
    filtered_data = controller.send(:filter_specs, gzipped_specs(upstream_specs))
    specs = parse_gzipped_specs(filtered_data)
    gem_names = specs.map(&:first)

    assert_includes gem_names, "new-gem", "Unknown gems pass through (lazy tracking on download)"
  end

  test "filter_specs fails closed when specs cannot be parsed" do
    controller = Api::SpecsController.new
    filtered_data = controller.send(:filter_specs, "invalid gzip")
    specs = parse_gzipped_specs(filtered_data)

    assert_empty specs
  end

  test "sync job excludes blocked and quarantined gems" do
    # Create blocked gem
    blocked_package = create(:gem_package, name: "blocked-gem")
    create(:gem_version, :blocked, gem_package: blocked_package, version: "1.0.0", platform: "ruby")

    # Create active quarantine
    create(:quarantined_version, name: "quarantined-gem", version: "2.0.0", platform: "ruby")

    # Stub upstream with blocked, quarantined, and unknown gems
    upstream_specs = [
      ["blocked-gem", Gem::Version.new("1.0.0"), "ruby"],
      ["quarantined-gem", Gem::Version.new("2.0.0"), "ruby"],
      ["unknown-gem", Gem::Version.new("3.0.0"), "ruby"]
    ]
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(upstream_specs))

    # Clear specs to trigger sync
    FileUtils.rm_rf(@specs_path)

    get "/specs.4.8.gz"

    assert_response :success

    specs = parse_gzipped_specs(response.body)
    gem_names = specs.map(&:first)

    refute_includes gem_names, "blocked-gem", "Blocked gems should be excluded"
    refute_includes gem_names, "quarantined-gem", "Quarantined gems should be excluded"
    assert_includes gem_names, "unknown-gem", "Unknown gems pass through"
  end

  private

  def create_specs_file(filename)
    File.binwrite(@specs_path.join(filename), gzipped_specs([["test", Gem::Version.new("1.0.0"), "ruby"]]))
  end

  def save_raw_specs(data)
    FileUtils.mkdir_p(@raw_specs_path)
    File.binwrite(@raw_specs_path.join("specs.4.8.gz"), data)
  end
end
