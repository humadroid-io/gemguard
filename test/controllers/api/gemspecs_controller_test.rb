require "test_helper"
require "webmock/minitest"

class Api::GemspecsControllerTest < ActionDispatch::IntegrationTest
  include SpecsTestHelper

  # Disable parallelization due to file system dependencies
  parallelize(workers: 1)

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    setup_test_specs_directory
    stub_specs_paths!
    @specs_path = SpecsTestHelper::TEST_SPECS_PATH.join("quick")
    FileUtils.mkdir_p(@specs_path)

    @gem_package = create(:gem_package, name: "rails")
  end

  teardown do
    WebMock.allow_net_connect!
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "show returns 404 for non-existent gemspec" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/nonexistent.json")
      .to_return(status: 404)

    get "/quick/Marshal.4.8/nonexistent-1.0.0.gemspec.rz"
    assert_response :not_found
  end

  test "show returns 404 for invalid gemspec filename" do
    # .txt files don't match the route constraint
    get "/quick/Marshal.4.8/invalid-file.txt"
    assert_response :not_found
  end

  test "show returns 403 for blocked gem" do
    create(:gem_version, :blocked, gem_package: @gem_package, version: "1.0.0")

    get "/quick/Marshal.4.8/rails-1.0.0.gemspec.rz"

    assert_response :forbidden
  end

  test "show returns 404 for actively quarantined gem" do
    create(:gem_version, :quarantined, gem_package: @gem_package, version: "1.0.0")

    get "/quick/Marshal.4.8/rails-1.0.0.gemspec.rz"

    assert_response :not_found
  end

  test "show serves approved gemspec" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/rails-1.0.0.gemspec.rz")
      .to_return(status: 200, body: "gemspec content")

    get "/quick/Marshal.4.8/rails-1.0.0.gemspec.rz"

    assert_response :success
    assert_equal "application/x-deflate", response.content_type
  end

  test "show downloads gemspec from upstream if not cached" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/rails-1.0.0.gemspec.rz")
      .to_return(status: 200, body: "gemspec content")

    get "/quick/Marshal.4.8/rails-1.0.0.gemspec.rz"

    assert_response :success
  end

  test "show serves gemspec with expired quarantine" do
    create(:gem_version, :expired_quarantine, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/rails-1.0.0.gemspec.rz")
      .to_return(status: 200, body: "gemspec content")

    get "/quick/Marshal.4.8/rails-1.0.0.gemspec.rz"

    assert_response :success
  end

  test "show handles platform-specific gemspecs" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0", platform: "x86_64-linux")
    stub_request(:get, "https://rubygems.org/quick/Marshal.4.8/rails-1.0.0-x86_64-linux.gemspec.rz")
      .to_return(status: 200, body: "gemspec content")

    get "/quick/Marshal.4.8/rails-1.0.0-x86_64-linux.gemspec.rz"

    assert_response :success
  end

  private

  def create_gemspec_file(filename)
    File.binwrite(@specs_path.join(filename), "fake gemspec content")
  end
end
