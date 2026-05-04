require "test_helper"
require "webmock/minitest"

# rubocop:disable Security/MarshalLoad
class Api::DependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "index proxies and returns dependency payload" do
    stub_versions("rails")
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
    stub_versions("blocked-gem")
    stub_versions("quarantined-gem")
    stub_versions("safe-gem")

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
    stub_versions("rails")
    stub_request(:get, "https://rubygems.org/api/v1/dependencies")
      .with(query: {"gems" => "rails"})
      .to_return(status: 500)

    get "/api/v1/dependencies", params: {gems: "rails"}

    assert_response :bad_gateway
  end

  test "index quarantines recently published versions before filtering dependency payload" do
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.hour.ago.iso8601}
    ])

    payload = [
      {"name" => "rails", "number" => "7.0.0", "platform" => "ruby"},
      {"name" => "rails", "number" => "7.1.0", "platform" => "ruby"}
    ]

    stub_request(:get, "https://rubygems.org/api/v1/dependencies")
      .with(query: {"gems" => "rails"})
      .to_return(status: 200, body: Marshal.dump(payload))

    get "/api/v1/dependencies", params: {gems: "rails"}

    assert_response :success
    assert QuarantinedVersion.exists?(name: "rails", version: "7.1.0", platform: "ruby")

    body = Marshal.load(response.body)
    numbers = body.map { |row| row["number"] }
    assert_equal ["7.0.0"], numbers
  end

  private

  def stub_versions(gem_name, versions = [])
    stub_request(:get, "https://rubygems.org/api/v1/versions/#{gem_name}.json")
      .to_return(status: 200, body: versions.to_json)
  end
end
# rubocop:enable Security/MarshalLoad
