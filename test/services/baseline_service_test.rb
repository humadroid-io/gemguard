# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class BaselineServiceTest < ActiveSupport::TestCase
  include SpecsTestHelper

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    setup_test_specs_directory
    stub_specs_paths!
    @specs_path = SpecsTestHelper::TEST_RAW_SPECS_PATH

    # Clear baseline settings
    Setting.set(:baseline_imported_at, nil)
    Setting.set(:baseline_source, nil)
  end

  teardown do
    WebMock.allow_net_connect!
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "baseline_imported? returns false by default" do
    refute BaselineService.baseline_imported?
  end

  test "baseline_imported? returns true after baseline import" do
    Setting.set(:baseline_imported_at, Time.current.iso8601)

    assert BaselineService.baseline_imported?
  end

  test "baseline_imported_at returns the timestamp" do
    timestamp = Time.current.iso8601
    Setting.set(:baseline_imported_at, timestamp)

    assert_equal timestamp, BaselineService.baseline_imported_at
  end

  test "baseline_source returns the source" do
    Setting.set(:baseline_source, "specs")

    assert_equal "specs", BaselineService.baseline_source
  end

  test "generate_baseline creates gzipped csv file" do
    specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["nokogiri", Gem::Version.new("1.15.0"), "x86_64-linux"]
    ]

    output_path = Rails.root.join("tmp", "test_baseline.csv.gz")

    # Stub the RubyGems endpoints
    gzipped_specs = build_gzipped_specs(specs)
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs)
    stub_request(:get, "https://rubygems.org/latest_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs)
    stub_request(:get, "https://rubygems.org/prerelease_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs)

    count = BaselineService.generate_baseline(output_path)
    assert_equal 2, count

    assert File.exist?(output_path)

    # Verify content
    content = Zlib::GzipReader.open(output_path, &:read)
    assert_includes content, "name,version,platform"
    assert_includes content, "rails,7.0.0,ruby"
    assert_includes content, "nokogiri,1.15.0,x86_64-linux"
  ensure
    File.delete(output_path) if output_path && File.exist?(output_path)
  end

  test "generate_baseline_from_local uses local specs files" do
    # Create local specs files
    FileUtils.mkdir_p(@specs_path)

    specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rack", Gem::Version.new("2.0.0"), "ruby"]
    ]

    File.binwrite(@specs_path.join("specs.4.8.gz"), build_gzipped_specs(specs))

    output_path = Rails.root.join("tmp", "test_local_baseline.csv.gz")

    count = BaselineService.generate_baseline_from_local(output_path)
    assert_equal 2, count

    content = Zlib::GzipReader.open(output_path, &:read)
    assert_includes content, "rails,7.0.0,ruby"
    assert_includes content, "rack,2.0.0,ruby"
  ensure
    File.delete(output_path) if output_path && File.exist?(output_path)
  end

  test "generate_baseline does NOT create database records" do
    specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    gzipped_specs = build_gzipped_specs(specs)

    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs)
    stub_request(:get, "https://rubygems.org/latest_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs)
    stub_request(:get, "https://rubygems.org/prerelease_specs.4.8.gz")
      .to_return(status: 200, body: gzipped_specs)

    output_path = Rails.root.join("tmp", "test_baseline.csv.gz")

    assert_no_difference ["GemPackage.count", "GemVersion.count"] do
      BaselineService.generate_baseline(output_path)
    end
  ensure
    File.delete(output_path) if output_path && File.exist?(output_path)
  end

  private

  def build_gzipped_specs(specs)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    io.string
  end
end
