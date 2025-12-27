require "test_helper"
require "webmock/minitest"

class RefreshTrackedGemsJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "only refreshes tracked gems" do
    # Create a tracked gem
    tracked_gem = create(:gem_package, name: "tracked-gem", tracked_at: Time.current)
    create(:gem_version, gem_package: tracked_gem, version: "1.0.0")

    # Create an untracked gem (e.g., from baseline import)
    untracked_gem = create(:gem_package, name: "untracked-gem", tracked_at: nil)
    create(:gem_version, gem_package: untracked_gem, version: "1.0.0")

    # Stub API calls for tracked gem only
    stub_request(:get, "https://rubygems.org/api/v1/versions/tracked-gem.json")
      .to_return(status: 200, body: [
        { "number" => "1.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 }
      ].to_json)

    # Should NOT make a request for untracked gem
    untracked_stub = stub_request(:get, "https://rubygems.org/api/v1/versions/untracked-gem.json")
      .to_return(status: 200, body: [].to_json)

    RefreshTrackedGemsJob.perform_now

    assert_not_requested untracked_stub
  end

  test "creates new versions for tracked gems" do
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [
        { "number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 },
        { "number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 }
      ].to_json)

    assert_difference "GemVersion.count", 1 do
      RefreshTrackedGemsJob.perform_now
    end

    assert gem_package.versions.exists?(version: "7.1.0")
  end

  test "quarantines recently published versions" do
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [
        { "number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 },
        { "number" => "7.1.0", "platform" => "ruby", "created_at" => 1.hour.ago.iso8601 }
      ].to_json)

    RefreshTrackedGemsJob.perform_now

    new_version = gem_package.versions.find_by(version: "7.1.0")
    assert new_version.quarantined?
  end

  test "approves older versions automatically" do
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [
        { "number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 },
        { "number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 }
      ].to_json)

    RefreshTrackedGemsJob.perform_now

    new_version = gem_package.versions.find_by(version: "7.1.0")
    assert new_version.approved?
  end

  test "handles empty versions list (all yanked)" do
    # RubyGems API simply excludes yanked versions from the response
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [].to_json)

    assert_no_difference "GemVersion.count" do
      RefreshTrackedGemsJob.perform_now
    end
  end

  test "handles API failure gracefully" do
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 500)

    assert_nothing_raised do
      RefreshTrackedGemsJob.perform_now
    end
  end

  test "triggers spec regeneration when new versions found" do
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [
        { "number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 },
        { "number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 }
      ].to_json)

    assert_enqueued_with(job: RegenerateFilteredSpecsJob) do
      RefreshTrackedGemsJob.perform_now
    end
  end

  test "does not regenerate specs when no new versions" do
    gem_package = create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 200, body: [
        { "number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601 }
      ].to_json)

    assert_no_enqueued_jobs(only: RegenerateFilteredSpecsJob) do
      RefreshTrackedGemsJob.perform_now
    end
  end
end
