require "test_helper"

class RegenerateFilteredSpecsJobTest < ActiveJob::TestCase
  include SpecsTestHelper

  setup do
    setup_test_specs_directory
    stub_specs_paths!
    @specs_dir = SpecsTestHelper::TEST_SPECS_PATH
    @raw_specs_dir = SpecsTestHelper::TEST_RAW_SPECS_PATH

    # Create sample raw specs
    @sample_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"],
      ["nokogiri", Gem::Version.new("1.15.0"), "ruby"]
    ]

    save_test_raw_specs(:all, gzipped_specs(@sample_specs))
  end

  teardown do
    restore_specs_paths!
    teardown_test_specs_directory
  end

  test "regenerates filtered specs without quarantined versions" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")

    RegenerateFilteredSpecsJob.perform_now(type: :all)

    filtered_specs = load_filtered_specs(:all)
    gem_names_versions = filtered_specs.map { |n, v, _| [n, v.to_s] }

    assert_includes gem_names_versions, ["rails", "7.0.0"]
    assert_not_includes gem_names_versions, ["rails", "7.1.0"]
    assert_includes gem_names_versions, ["nokogiri", "1.15.0"]
  end

  test "regenerates filtered specs without blocked versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, :blocked, gem_package: gem_package, version: "7.1.0", platform: "ruby")

    RegenerateFilteredSpecsJob.perform_now(type: :all)

    filtered_specs = load_filtered_specs(:all)
    gem_names_versions = filtered_specs.map { |n, v, _| [n, v.to_s] }

    assert_includes gem_names_versions, ["rails", "7.0.0"]
    assert_not_includes gem_names_versions, ["rails", "7.1.0"]
  end

  test "does nothing when no raw specs exist" do
    FileUtils.rm_rf(@raw_specs_dir)

    assert_nothing_raised do
      RegenerateFilteredSpecsJob.perform_now(type: :all)
    end
  end

  private

  def load_filtered_specs(type)
    filename = {
      all: "specs.4.8.gz",
      latest: "latest_specs.4.8.gz",
      prerelease: "prerelease_specs.4.8.gz"
    }[type]

    path = @specs_dir.join(filename)
    return [] unless File.exist?(path)

    parse_gzipped_specs(File.binread(path))
  end
end
