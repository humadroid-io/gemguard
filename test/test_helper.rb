ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Helper module for tests that need to work with specs files
# Uses tmp/test_specs instead of storage/specs to avoid deleting development data
module SpecsTestHelper
  TEST_SPECS_PATH = Rails.root.join("tmp", "test_specs")
  TEST_RAW_SPECS_PATH = TEST_SPECS_PATH.join("raw")

  def setup_test_specs_directory
    FileUtils.rm_rf(TEST_SPECS_PATH)
    FileUtils.mkdir_p(TEST_SPECS_PATH)
    FileUtils.mkdir_p(TEST_RAW_SPECS_PATH)
  end

  def teardown_test_specs_directory
    FileUtils.rm_rf(TEST_SPECS_PATH)
  end

  def stub_specs_paths!
    # Stub SyncSpecsJob
    SyncSpecsJob.class_eval do
      define_method(:raw_specs_path) { SpecsTestHelper::TEST_RAW_SPECS_PATH }
      define_method(:filtered_specs_path) { SpecsTestHelper::TEST_SPECS_PATH }
    end

    # Stub RegenerateFilteredSpecsJob
    RegenerateFilteredSpecsJob.class_eval do
      define_method(:raw_specs_path) { SpecsTestHelper::TEST_RAW_SPECS_PATH }
      define_method(:filtered_specs_path) { SpecsTestHelper::TEST_SPECS_PATH }
    end

    # Stub SpecsBaselineImporter
    SpecsBaselineImporter.class_eval do
      define_singleton_method(:raw_specs_path) { SpecsTestHelper::TEST_RAW_SPECS_PATH }
      define_singleton_method(:filtered_specs_path) { SpecsTestHelper::TEST_SPECS_PATH }
    end

    # Stub Api::SpecsController
    Api::SpecsController.class_eval do
      define_method(:filtered_specs_path) { SpecsTestHelper::TEST_SPECS_PATH }
    end

    # Stub SpecsAvailabilityService
    SpecsAvailabilityService.class_eval do
      define_singleton_method(:raw_specs_path) { SpecsTestHelper::TEST_RAW_SPECS_PATH }
    end

    # Stub BaselineService
    BaselineService.class_eval do
      define_singleton_method(:raw_specs_path) { SpecsTestHelper::TEST_RAW_SPECS_PATH }
    end
  end

  def restore_specs_paths!
    SyncSpecsJob.class_eval do
      define_method(:raw_specs_path) { Rails.root.join("storage", "specs", "raw") }
      define_method(:filtered_specs_path) { Rails.root.join("storage", "specs") }
    end

    RegenerateFilteredSpecsJob.class_eval do
      define_method(:raw_specs_path) { Rails.root.join("storage", "specs", "raw") }
      define_method(:filtered_specs_path) { Rails.root.join("storage", "specs") }
    end

    SpecsBaselineImporter.class_eval do
      define_singleton_method(:raw_specs_path) { Rails.root.join("storage", "specs", "raw") }
      define_singleton_method(:filtered_specs_path) { Rails.root.join("storage", "specs") }
    end

    Api::SpecsController.class_eval do
      define_method(:filtered_specs_path) { Rails.root.join("storage", "specs") }
    end

    SpecsAvailabilityService.class_eval do
      define_singleton_method(:raw_specs_path) { Rails.root.join("storage", "specs", "raw") }
    end

    BaselineService.class_eval do
      define_singleton_method(:raw_specs_path) { Rails.root.join("storage", "specs", "raw") }
    end
  end

  def gzipped_specs(specs)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    io.string
  end

  def parse_gzipped_specs(data)
    gz = Zlib::GzipReader.new(StringIO.new(data))
    Marshal.load(gz.read)
  end

  def save_test_raw_specs(type, data)
    filename = case type
    when :all then "specs.4.8.gz"
    when :latest then "latest_specs.4.8.gz"
    when :prerelease then "prerelease_specs.4.8.gz"
    end
    File.binwrite(TEST_RAW_SPECS_PATH.join(filename), data)
  end

  def save_test_filtered_specs(type, data)
    filename = case type
    when :all then "specs.4.8.gz"
    when :latest then "latest_specs.4.8.gz"
    when :prerelease then "prerelease_specs.4.8.gz"
    end
    File.binwrite(TEST_SPECS_PATH.join(filename), data)
  end
end

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods

    parallelize(workers: :number_of_processors)

    # Clean database between tests
    setup do
      AppDependencyEdge.delete_all if defined?(AppDependencyEdge)
      AppGemVersion.delete_all if defined?(AppGemVersion)
      ManagedApp.delete_all if defined?(ManagedApp)
      GemPackage.delete_all
      GemVersion.delete_all
      QuarantineRule.delete_all
      QuarantinedVersion.delete_all
      AuditLog.delete_all
      Setting.delete_all
    end
  end
end

class ActionDispatch::IntegrationTest
  include FactoryBot::Syntax::Methods
end
