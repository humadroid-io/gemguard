require "test_helper"
require "webmock/minitest"

class ImportSpecsBaselineJobTest < ActiveJob::TestCase
  include SpecsTestHelper

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    setup_test_specs_directory
    stub_specs_paths!
    @specs_path = SpecsTestHelper::TEST_SPECS_PATH

    Setting.set(:baseline_imported_at, nil)
    Setting.set(:baseline_source, nil)
  end

  teardown do
    WebMock.allow_net_connect!
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "imports specs and marks baseline as imported" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    ImportSpecsBaselineJob.perform_now

    assert Setting.baseline_imported?
    assert_equal "specs", Setting.get(:baseline_source)
  end

  test "does NOT create database records" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rack", Gem::Version.new("2.0.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    assert_no_difference ["GemPackage.count", "GemVersion.count"] do
      ImportSpecsBaselineJob.perform_now
    end
  end

  test "saves specs files to storage" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:prerelease, [])

    ImportSpecsBaselineJob.perform_now

    assert File.exist?(@specs_path.join("raw", "specs.4.8.gz"))
    assert File.exist?(@specs_path.join("specs.4.8.gz"))
  end

  test "enqueues spec regeneration after import" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      ImportSpecsBaselineJob.perform_now
    end
  end

  test "passes include_prerelease option" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]])

    ImportSpecsBaselineJob.perform_now(include_prerelease: true)

    # Prerelease specs should be in filtered directory (not just raw)
    assert File.exist?(@specs_path.join("prerelease_specs.4.8.gz"))
  end

  private

  def stub_specs(type, specs)
    filename = case type
    when :latest then "latest_specs.4.8.gz"
    when :prerelease then "prerelease_specs.4.8.gz"
    else "specs.4.8.gz"
    end

    stub_request(:get, "https://rubygems.org/#{filename}")
      .to_return(status: 200, body: gzipped_specs(specs))
  end

  def gzipped_specs(specs)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    io.string
  end
end
