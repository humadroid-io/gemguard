require "test_helper"
require "webmock/minitest"

class Api::GemsControllerTest < ActionDispatch::IntegrationTest
  # Disable parallelization due to file system dependencies
  parallelize(workers: 1)

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @gems_path = Rails.root.join("storage", "gems")
    FileUtils.mkdir_p(@gems_path)

    @gem_package = create(:gem_package, name: "rails")
  end

  teardown do
    WebMock.allow_net_connect!
    FileUtils.rm_rf(@gems_path)
  end

  test "show returns 404 for non-existent gem" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/nonexistent.json")
      .to_return(status: 404)

    get "/gems/nonexistent-1.0.0.gem"
    assert_response :not_found
  end

  test "show returns 404 for invalid gem filename" do
    # .txt files don't match the route constraint, so they return 404
    get "/gems/invalid-file.txt"
    assert_response :not_found
  end

  test "show returns 403 for blocked gem" do
    create(:gem_version, :blocked, gem_package: @gem_package, version: "1.0.0")

    get "/gems/rails-1.0.0.gem"

    assert_response :forbidden
  end

  test "show returns 503 for actively quarantined gem" do
    create(:gem_version, :quarantined, gem_package: @gem_package, version: "1.0.0")

    get "/gems/rails-1.0.0.gem"

    assert_response :service_unavailable
    assert_equal "300", response.headers["Retry-After"]
  end

  test "show serves approved gem" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/gems/rails-1.0.0.gem")
      .to_return(status: 200, body: "gem content")

    get "/gems/rails-1.0.0.gem"

    assert_response :success
    assert_equal "application/octet-stream", response.content_type
  end

  test "show downloads gem from upstream if not cached" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/gems/rails-1.0.0.gem")
      .to_return(status: 200, body: "gem content")

    get "/gems/rails-1.0.0.gem"

    assert_response :success
    assert File.exist?(@gems_path.join("rails-1.0.0.gem"))
  end

  test "show serves quarantined gem with expired quarantine" do
    create(:gem_version, :expired_quarantine, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/gems/rails-1.0.0.gem")
      .to_return(status: 200, body: "gem content")

    get "/gems/rails-1.0.0.gem"

    assert_response :success
  end

  test "show creates audit log for downloads" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/gems/rails-1.0.0.gem")
      .to_return(status: 200, body: "gem content")

    assert_difference "AuditLog.count", 1 do
      get "/gems/rails-1.0.0.gem"
    end

    log = AuditLog.last
    assert_equal "rails", log.gem_name
    assert_equal "1.0.0", log.version
    assert_equal "download", log.action
  end

  test "show handles platform-specific gems" do
    create(:gem_version, :approved, gem_package: @gem_package, version: "1.0.0", platform: "java")
    stub_request(:get, "https://rubygems.org/gems/rails-1.0.0-java.gem")
      .to_return(status: 200, body: "gem content")

    get "/gems/rails-1.0.0-java.gem"

    assert_response :success
  end

  test "show handles gems with hyphens in name" do
    pkg = create(:gem_package, name: "activerecord-import")
    create(:gem_version, :approved, gem_package: pkg, version: "1.0.0")
    stub_request(:get, "https://rubygems.org/gems/activerecord-import-1.0.0.gem")
      .to_return(status: 200, body: "gem content")

    get "/gems/activerecord-import-1.0.0.gem"

    assert_response :success
  end

  private

  def create_gem_file(filename)
    File.binwrite(@gems_path.join(filename), "fake gem content")
  end
end
