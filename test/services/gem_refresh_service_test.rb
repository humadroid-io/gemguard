require "test_helper"
require "webmock/minitest"

class GemRefreshServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @gem_package = create(:gem_package, name: "rails")
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "updates gem info from RubyGems API" do
    stub_gem_info("rails", info: "Ruby on Rails", homepage_uri: "https://rubyonrails.org", downloads: 500_000_000)
    stub_versions("rails", [])

    service = GemRefreshService.new(@gem_package)
    assert service.call

    @gem_package.reload
    assert_equal "Ruby on Rails", @gem_package.info
    assert_equal "https://rubyonrails.org", @gem_package.homepage_url
    assert_equal 500_000_000, @gem_package.downloads_count
  end

  test "creates new versions from API" do
    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    service = GemRefreshService.new(@gem_package)

    assert_difference "GemVersion.count", 2 do
      assert service.call
    end

    assert_equal 2, service.new_versions_count
    assert @gem_package.versions.exists?(version: "7.0.0")
    assert @gem_package.versions.exists?(version: "7.1.0")
  end

  test "does not duplicate existing versions" do
    create(:gem_version, gem_package: @gem_package, version: "7.0.0", platform: "ruby")

    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    service = GemRefreshService.new(@gem_package)

    assert_difference "GemVersion.count", 1 do
      assert service.call
    end

    assert_equal 1, service.new_versions_count
  end

  test "updates published_at for existing versions if missing" do
    version = create(:gem_version, gem_package: @gem_package, version: "7.0.0", platform: "ruby", published_at: nil)
    published_time = 1.year.ago

    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => published_time.iso8601}
    ])

    service = GemRefreshService.new(@gem_package)
    assert service.call

    version.reload
    assert_not_nil version.published_at
  end

  test "quarantines recently published versions" do
    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "7.2.0", "platform" => "ruby", "created_at" => 1.hour.ago.iso8601}
    ])

    service = GemRefreshService.new(@gem_package)
    assert service.call

    version = @gem_package.versions.find_by(version: "7.2.0")
    assert version.quarantined?
    assert QuarantinedVersion.exists?(name: "rails", version: "7.2.0", platform: "ruby")
  end

  test "approves old versions automatically" do
    stub_gem_info("rails")
    stub_versions("rails", [
      {"number" => "6.0.0", "platform" => "ruby", "created_at" => 2.years.ago.iso8601}
    ])

    service = GemRefreshService.new(@gem_package)
    assert service.call

    version = @gem_package.versions.find_by(version: "6.0.0")
    assert version.approved?
  end

  test "handles empty versions list (all yanked)" do
    # RubyGems API simply excludes yanked versions from the response
    stub_gem_info("rails")
    stub_versions("rails", [])

    service = GemRefreshService.new(@gem_package)

    assert_no_difference "GemVersion.count" do
      assert service.call
    end

    assert_equal 0, service.new_versions_count
  end

  test "handles gem info API failure" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/rails.json")
      .to_return(status: 404)
    stub_versions("rails", [])

    service = GemRefreshService.new(@gem_package)
    assert_not service.call
    assert_includes service.errors, "Could not fetch gem info from RubyGems"
  end

  test "handles versions API failure" do
    stub_gem_info("rails")
    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 500)

    service = GemRefreshService.new(@gem_package)
    assert_not service.call
    assert service.errors.any? { |e| e.include?("Could not fetch versions") }
  end

  test "handles invalid JSON response" do
    stub_gem_info("rails")
    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: "invalid json")

    service = GemRefreshService.new(@gem_package)
    assert_not service.call
    assert service.errors.any? { |e| e.include?("Invalid JSON") }
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
