require "test_helper"

class SpecsAvailabilityServiceTest < ActiveSupport::TestCase
  setup do
    @specs_path = Rails.root.join("storage", "specs", "raw")
    FileUtils.rm_rf(@specs_path)
  end

  teardown do
    FileUtils.rm_rf(@specs_path)
  end

  test "available? returns false when no specs exist" do
    assert_not SpecsAvailabilityService.available?
  end

  test "available? returns true when at least one spec file exists" do
    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")

    assert SpecsAvailabilityService.available?
  end

  test "all_available? returns false when some specs missing" do
    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")

    assert_not SpecsAvailabilityService.all_available?
  end

  test "all_available? returns true when all specs exist" do
    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")
    File.write(@specs_path.join("latest_specs.4.8.gz"), "test")
    File.write(@specs_path.join("prerelease_specs.4.8.gz"), "test")

    assert SpecsAvailabilityService.all_available?
  end

  test "missing_specs returns list of missing files" do
    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")

    missing = SpecsAvailabilityService.missing_specs
    assert_includes missing, "latest_specs.4.8.gz"
    assert_includes missing, "prerelease_specs.4.8.gz"
    assert_not_includes missing, "specs.4.8.gz"
  end

  test "status returns :unavailable when no specs" do
    assert_equal :unavailable, SpecsAvailabilityService.status
  end

  test "status returns :partial when some specs exist" do
    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")

    assert_equal :partial, SpecsAvailabilityService.status
  end

  test "status returns :ready when all specs exist" do
    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")
    File.write(@specs_path.join("latest_specs.4.8.gz"), "test")
    File.write(@specs_path.join("prerelease_specs.4.8.gz"), "test")

    assert_equal :ready, SpecsAvailabilityService.status
  end

  test "status_message returns appropriate message for each status" do
    assert_match /not been synced/, SpecsAvailabilityService.status_message

    FileUtils.mkdir_p(@specs_path)
    File.write(@specs_path.join("specs.4.8.gz"), "test")
    assert_match /missing/, SpecsAvailabilityService.status_message

    File.write(@specs_path.join("latest_specs.4.8.gz"), "test")
    File.write(@specs_path.join("prerelease_specs.4.8.gz"), "test")
    assert_match /ready/, SpecsAvailabilityService.status_message
  end
end
