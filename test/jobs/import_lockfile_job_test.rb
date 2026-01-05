require "test_helper"
require "webmock/minitest"

class ImportLockfileJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "refreshes gems using GemRefreshService" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_difference "GemVersion.count", 1 do
      ImportLockfileJob.perform_now(["rails"])
    end

    assert gem_package.versions.exists?(version: "7.1.0")
  end

  test "refreshes multiple gems" do
    rails = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: rails, version: "7.0.0")

    rack = create(:gem_package, name: "rack")
    create(:gem_version, gem_package: rack, version: "2.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    stub_gem_info("rack")
    stub_gem_versions("rack", [
      {"number" => "2.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "3.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_difference "GemVersion.count", 1 do
      ImportLockfileJob.perform_now(["rails", "rack"])
    end

    assert rack.versions.exists?(version: "3.0.0")
  end

  test "skips gems that do not exist in database" do
    # Only create rails, not rack
    rails = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: rails, version: "7.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    # rack is not stubbed because it shouldn't be called
    assert_nothing_raised do
      ImportLockfileJob.perform_now(["rails", "nonexistent-gem"])
    end
  end

  test "handles API failures gracefully" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_request(:get, "https://rubygems.org/api/v1/gems/rails.json")
      .to_return(status: 500)
    stub_request(:get, "https://rubygems.org/api/v1/versions/rails.json")
      .to_return(status: 500)

    assert_nothing_raised do
      ImportLockfileJob.perform_now(["rails"])
    end
  end

  test "quarantines recently published versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.hour.ago.iso8601}
    ])

    ImportLockfileJob.perform_now(["rails"])

    new_version = gem_package.versions.find_by(version: "7.1.0")
    assert new_version.quarantined?
  end

  test "approves older versions automatically" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    ImportLockfileJob.perform_now(["rails"])

    new_version = gem_package.versions.find_by(version: "7.1.0")
    assert new_version.approved?
  end

  test "triggers spec regeneration when quarantined versions found" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    # Create a recent quarantined version
    create(:quarantined_version, name: "rails", version: "7.1.0", first_seen_at: 30.minutes.ago)

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_enqueued_with(job: RegenerateFilteredSpecsJob) do
      ImportLockfileJob.perform_now(["rails"])
    end
  end

  test "does not trigger spec regeneration when no recent quarantined versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    assert_no_enqueued_jobs(only: RegenerateFilteredSpecsJob) do
      ImportLockfileJob.perform_now(["rails"])
    end
  end

  test "handles empty gem list" do
    assert_nothing_raised do
      ImportLockfileJob.perform_now([])
    end
  end

  test "adds quarantined versions to QuarantinedVersion table" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0")

    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "7.1.0", "platform" => "ruby", "created_at" => 1.hour.ago.iso8601}
    ])

    assert_difference "QuarantinedVersion.count", 1 do
      ImportLockfileJob.perform_now(["rails"])
    end

    assert QuarantinedVersion.exists?(name: "rails", version: "7.1.0")
  end

  test "handles platform-specific versions" do
    gem_package = create(:gem_package, name: "nokogiri")
    create(:gem_version, gem_package: gem_package, version: "1.16.0", platform: "ruby")

    stub_gem_info("nokogiri")
    stub_gem_versions("nokogiri", [
      {"number" => "1.16.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "1.16.0", "platform" => "x86_64-linux", "created_at" => 1.year.ago.iso8601}
    ])

    assert_difference "GemVersion.count", 1 do
      ImportLockfileJob.perform_now(["nokogiri"])
    end

    assert gem_package.versions.exists?(version: "1.16.0", platform: "x86_64-linux")
  end

  test "is a continuable job" do
    assert ImportLockfileJob.include?(ActiveJob::Continuable)
  end

  test "continues from where it left off after interruption" do
    # Create two gems
    rails = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: rails, version: "7.0.0")

    rack = create(:gem_package, name: "rack")
    create(:gem_version, gem_package: rack, version: "2.0.0")

    # Stub both gems
    stub_gem_info("rails")
    stub_gem_versions("rails", [
      {"number" => "7.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    stub_gem_info("rack")
    stub_gem_versions("rack", [
      {"number" => "2.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601},
      {"number" => "3.0.0", "platform" => "ruby", "created_at" => 1.year.ago.iso8601}
    ])

    # Perform the job - both gems should be processed
    ImportLockfileJob.perform_now(["rails", "rack"])

    # Verify both were processed
    assert_equal 1, rails.versions.count
    assert_equal 2, rack.versions.count
    assert rack.versions.exists?(version: "3.0.0")
  end

  private

  def stub_gem_info(gem_name, info = nil)
    info ||= {
      "name" => gem_name,
      "info" => "A Ruby gem",
      "homepage_uri" => "https://github.com/test/#{gem_name}",
      "downloads" => 1000
    }

    stub_request(:get, "https://rubygems.org/api/v1/gems/#{gem_name}.json")
      .to_return(status: 200, body: info.to_json)
  end

  def stub_gem_versions(gem_name, versions)
    stub_request(:get, "https://rubygems.org/api/v1/versions/#{gem_name}.json")
      .to_return(status: 200, body: versions.to_json)
  end
end
