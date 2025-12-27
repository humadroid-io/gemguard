require "test_helper"
require "webmock/minitest"

class SyncSpecsJobTest < ActiveJob::TestCase
  # Disable parallelization due to file system dependencies
  parallelize(workers: 1)

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @specs_path = Rails.root.join("storage", "specs")
    FileUtils.rm_rf(@specs_path)
    FileUtils.mkdir_p(@specs_path)
  end

  teardown do
    WebMock.allow_net_connect!
    FileUtils.rm_rf(@specs_path)
  end

  test "saves specs file to storage" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([["rails", "7.0.0", "ruby"]]))

    SyncSpecsJob.perform_now

    assert File.exist?(@specs_path.join("specs.4.8.gz"))
  end

  test "does not create database records" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["rails", Gem::Version.new("7.0.0"), "ruby"],
        ["rack", Gem::Version.new("2.0.0"), "ruby"]
      ]))

    assert_no_difference ["GemPackage.count", "GemVersion.count"] do
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

  test "does not quarantine gems on sync - tracking happens on download" do
    # SyncSpecsJob no longer tracks new gems
    # Gems are tracked lazily when downloaded via GemsController
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs([
        ["rails", Gem::Version.new("7.0.0"), "ruby"],
        ["rack", Gem::Version.new("2.0.0"), "ruby"]
      ]))

    assert_no_difference "QuarantinedVersion.count" do
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

  test "passes through unknown gems - lazy tracking" do
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

    assert_includes gem_names, "unknown-gem", "Unknown gems pass through (tracked on download)"
  end

  private

  def save_raw_specs(type, data)
    raw_path = @specs_path.join("raw")
    FileUtils.mkdir_p(raw_path)

    filename = case type
    when :all then "specs.4.8.gz"
    when :latest then "latest_specs.4.8.gz"
    when :prerelease then "prerelease_specs.4.8.gz"
    end

    File.binwrite(raw_path.join(filename), data)
  end

  def parse_gzipped_specs(data)
    gz = Zlib::GzipReader.new(StringIO.new(data))
    Marshal.load(gz.read)
  end

  def gzipped_specs(specs)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    io.string
  end
end
