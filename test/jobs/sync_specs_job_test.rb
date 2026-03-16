require "test_helper"
require "webmock/minitest"

class SyncSpecsJobTest < ActiveJob::TestCase
  include SpecsTestHelper

  # Disable parallelization due to file system dependencies
  parallelize(workers: 1)

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    setup_test_specs_directory
    stub_specs_paths!
    @specs_path = SpecsTestHelper::TEST_SPECS_PATH
    @raw_specs_path = SpecsTestHelper::TEST_RAW_SPECS_PATH
  end

  teardown do
    WebMock.allow_net_connect!
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "saves raw and filtered specs files" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", Gem::Version.new("7.0.0"), "ruby"]]))

    SyncSpecsJob.perform_now

    assert File.exist?(@raw_specs_path.join("specs.4.8.gz")), "Raw specs should be saved"
    assert File.exist?(@specs_path.join("specs.4.8.gz")), "Filtered specs should be saved"
  end

  test "does not create GemPackage or GemVersion records" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["rails", Gem::Version.new("7.0.0"), "ruby"],
        ["rack", Gem::Version.new("2.0.0"), "ruby"]
      ]))

    assert_no_difference ["GemPackage.count", "GemVersion.count"] do
      SyncSpecsJob.perform_now
    end
  end

  test "detects new versions and adds to quarantine" do
    # First sync establishes baseline
    previous_specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    # New sync has additional version
    current_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"]  # New!
    ]
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    assert_difference "QuarantinedVersion.count", 1 do
      SyncSpecsJob.perform_now
    end

    assert QuarantinedVersion.exists?(name: "rails", version: "7.1.0")
  end

  test "does not add existing versions to quarantine" do
    # Previous specs
    previous_specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    # Same specs again
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(previous_specs))

    assert_no_difference "QuarantinedVersion.count" do
      SyncSpecsJob.perform_now
    end
  end

  test "handles first sync with no previous specs" do
    # No previous specs - first sync after baseline
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["rails", Gem::Version.new("7.0.0"), "ruby"]
      ]))

    # Should not quarantine anything on first sync
    assert_no_difference "QuarantinedVersion.count" do
      SyncSpecsJob.perform_now
    end
  end

  test "syncs latest specs" do
    stub_request(:get, "https://rubygems.org/latest_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", Gem::Version.new("7.0.0"), "ruby"]]))

    SyncSpecsJob.perform_now(type: :latest)

    assert File.exist?(@specs_path.join("latest_specs.4.8.gz"))
  end

  test "syncs prerelease specs" do
    stub_request(:get, "https://rubygems.org/prerelease_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]]))

    SyncSpecsJob.perform_now(type: :prerelease)

    assert File.exist?(@specs_path.join("prerelease_specs.4.8.gz"))
  end

  test "handles fetch failure gracefully" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 500)

    assert_nothing_raised do
      SyncSpecsJob.perform_now
    end
  end

  test "excludes blocked gems from filtered specs" do
    # Create blocked gem
    gem_package = create(:gem_package, name: "blocked-gem")
    create(:gem_version, gem_package: gem_package, version: "1.0.0", status: :blocked)

    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["rails", Gem::Version.new("7.0.0"), "ruby"],
        ["blocked-gem", Gem::Version.new("1.0.0"), "ruby"]
      ]))

    SyncSpecsJob.perform_now

    # Read filtered specs
    filtered_path = @specs_path.join("specs.4.8.gz")
    filtered_specs = parse_gzipped_specs(File.binread(filtered_path))
    gem_names = filtered_specs.map(&:first)

    assert_includes gem_names, "rails", "Unknown gems pass through"
    refute_includes gem_names, "blocked-gem", "Blocked gems should be excluded"
  end

  test "excludes active quarantine from filtered specs" do
    # Create active quarantine entry
    create(:quarantined_version, name: "quarantined-gem", version: "1.0.0", platform: "ruby")

    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["rails", Gem::Version.new("7.0.0"), "ruby"],
        ["quarantined-gem", Gem::Version.new("1.0.0"), "ruby"]
      ]))

    SyncSpecsJob.perform_now

    # Read filtered specs
    filtered_path = @specs_path.join("specs.4.8.gz")
    filtered_specs = parse_gzipped_specs(File.binread(filtered_path))
    gem_names = filtered_specs.map(&:first)

    assert_includes gem_names, "rails", "Unknown gems pass through"
    refute_includes gem_names, "quarantined-gem", "Quarantined gems should be excluded"
  end

  test "passes through unknown gems" do
    # No gems in database - unknown gems should pass through
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["unknown-gem", Gem::Version.new("1.0.0"), "ruby"]
      ]))

    SyncSpecsJob.perform_now

    # Read filtered specs
    filtered_path = @specs_path.join("specs.4.8.gz")
    filtered_specs = parse_gzipped_specs(File.binread(filtered_path))
    gem_names = filtered_specs.map(&:first)

    assert_includes gem_names, "unknown-gem", "Unknown gems pass through"
  end

  test "handles different platforms in diff detection" do
    # Previous: only ruby platform
    previous_specs = [["nokogiri", Gem::Version.new("1.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    # Current: adds linux platform
    current_specs = [
      ["nokogiri", Gem::Version.new("1.0.0"), "ruby"],
      ["nokogiri", Gem::Version.new("1.0.0"), "x86_64-linux"]  # New platform!
    ]
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    assert_difference "QuarantinedVersion.count", 1 do
      SyncSpecsJob.perform_now
    end

    assert QuarantinedVersion.exists?(name: "nokogiri", version: "1.0.0", platform: "x86_64-linux")
    refute QuarantinedVersion.exists?(name: "nokogiri", version: "1.0.0", platform: "ruby")
  end

  test "upserts quarantined versions without duplicates" do
    # Previous specs
    previous_specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    # Add new version
    current_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"]
    ]
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    # Run twice - should not create duplicate
    SyncSpecsJob.perform_now

    # Update raw specs for second run
    save_raw_specs(:all, gzipped_specs(current_specs))

    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    # Second run should not add duplicates
    assert_no_difference "QuarantinedVersion.count" do
      SyncSpecsJob.perform_now
    end
  end

  test "skips quarantine tracking during grace period after baseline import" do
    # Simulate baseline just imported
    Setting.set(:baseline_imported_at, Time.current.iso8601)

    # Previous specs
    previous_specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    # New version appears
    current_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"]
    ]
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    # Should NOT add to quarantine during grace period
    assert_no_difference "QuarantinedVersion.count" do
      SyncSpecsJob.perform_now
    end

    # But specs should still be saved
    assert File.exist?(@specs_path.join("specs.4.8.gz"))
  end

  test "tracks quarantine after grace period expires" do
    # Simulate baseline imported 15 minutes ago
    Setting.set(:baseline_imported_at, 15.minutes.ago.iso8601)

    # Previous specs
    previous_specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    # New version appears
    current_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"]
    ]
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    # Should add to quarantine after grace period
    assert_difference "QuarantinedVersion.count", 1 do
      SyncSpecsJob.perform_now
    end
  end

  test "enqueues metadata refresh for tracked gems with newly detected versions" do
    create(:gem_package, name: "rails", tracked_at: Time.current)
    create(:gem_package, name: "rack", tracked_at: nil)

    previous_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rack", Gem::Version.new("3.0.0"), "ruby"]
    ]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    current_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"],
      ["rack", Gem::Version.new("3.0.0"), "ruby"],
      ["rack", Gem::Version.new("3.1.0"), "ruby"]
    ]

    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    assert_enqueued_with(job: RefreshGemMetadataJob, args: [["rails"]]) do
      SyncSpecsJob.perform_now
    end
  end

  test "does not enqueue metadata refresh for untracked gems" do
    previous_specs = [["rack", Gem::Version.new("3.0.0"), "ruby"]]
    save_raw_specs(:all, gzipped_specs(previous_specs))

    current_specs = [
      ["rack", Gem::Version.new("3.0.0"), "ruby"],
      ["rack", Gem::Version.new("3.1.0"), "ruby"]
    ]

    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs(current_specs))

    assert_no_enqueued_jobs(only: RefreshGemMetadataJob) do
      SyncSpecsJob.perform_now
    end
  end

  private

  def save_raw_specs(type, data)
    save_test_raw_specs(type, data)
  end
end
