require "test_helper"
require "webmock/minitest"

class RefreshGemMetadataJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "refreshes full metadata for tracked gems only" do
    tracked_gem = create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_version, gem_package: tracked_gem, version: "7.1.0", platform: "ruby")

    create(:gem_package, name: "rack", tracked_at: nil)

    stub_request(:get, "https://rubygems.org/api/v1/gems/rails.json")
      .to_return(status: 200, body: {
        "name" => "rails",
        "info" => "Ruby on Rails",
        "homepage_uri" => "https://rubyonrails.org",
        "downloads" => 500_000_000
      }.to_json)

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [
        {"number" => "6.1.0", "platform" => "ruby", "created_at" => 2.years.ago.iso8601},
        {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
        {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.day.ago.iso8601}
      ].to_json)

    rack_stub = stub_request(:get, "https://rubygems.org/api/v1/versions/rack.json")
      .to_return(status: 200, body: [].to_json)

    assert_difference "GemVersion.count", 2 do
      RefreshGemMetadataJob.perform_now(%w[rails rack])
    end

    tracked_gem.reload
    assert_equal "Ruby on Rails", tracked_gem.info
    assert tracked_gem.versions.exists?(version: "6.1.0", platform: "ruby")
    assert tracked_gem.versions.exists?(version: "7.0.0", platform: "ruby")
    assert_not_requested rack_stub
  end
end
