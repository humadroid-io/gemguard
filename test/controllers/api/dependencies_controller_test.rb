require "test_helper"
require "webmock/minitest"

class Api::DependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "index proxies and returns dependency payload" do
    stub_request(:get, "https://rubygems.org/api/v1/dependencies")
      .with(query: {"gems" => "rails"})
      .to_return(status: 200, body: Marshal.dump([{"name" => "rails", "number" => "7.1.0", "platform" => "ruby"}]))

    get "/api/v1/dependencies", params: {gems: "rails"}

    assert_response :success
    body = Marshal.load(response.body)
    assert_equal "rails", body.first["name"]
  end

  test "index filters blocked and quarantined versions" do
    blocked_package = create(:gem_package, name: "blocked-gem")
    create(:gem_version, :blocked, gem_package: blocked_package, version: "1.0.0", platform: "ruby")
    create(:quarantined_version, name: "quarantined-gem", version: "2.0.0", platform: "java")

    payload = [
      {"name" => "blocked-gem", "number" => "1.0.0", "platform" => "ruby"},
      {"name" => "quarantined-gem", "number" => "2.0.0", "platform" => "java"},
      {"name" => "safe-gem", "number" => "3.0.0", "platform" => "ruby"}
    ]

    stub_request(:get, "https://rubygems.org/api/v1/dependencies")
      .with(query: {"gems" => "blocked-gem,quarantined-gem,safe-gem"})
      .to_return(status: 200, body: Marshal.dump(payload))

    get "/api/v1/dependencies", params: {gems: "blocked-gem,quarantined-gem,safe-gem"}

    assert_response :success

    body = Marshal.load(response.body)
    names = body.map { |row| row["name"] }

    assert_equal ["safe-gem"], names
  end

  test "index returns bad request when gems param missing" do
    get "/api/v1/dependencies"

    assert_response :bad_request
  end

  test "index returns bad gateway when upstream fails" do
    stub_request(:get, "https://rubygems.org/api/v1/dependencies")
      .with(query: {"gems" => "rails"})
      .to_return(status: 500)

    get "/api/v1/dependencies", params: {gems: "rails"}

    assert_response :bad_gateway
  end
end
