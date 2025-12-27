# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class BaselineServiceTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "import_from_csv creates approved gem versions" do
    csv_data = <<~CSV
      name,version,platform
      rails,7.0.0,ruby
      nokogiri,1.15.0,ruby
      nokogiri,1.15.0,x86_64-linux
    CSV

    count = BaselineService.import_from_csv(csv_data)

    assert_equal 3, count
    assert_equal 2, GemPackage.count
    assert_equal 3, GemVersion.count

    rails_version = GemVersion.joins(:gem_package).find_by(gem_packages: { name: "rails" })
    assert rails_version.approved?

    nokogiri_versions = GemVersion.joins(:gem_package).where(gem_packages: { name: "nokogiri" })
    assert_equal 2, nokogiri_versions.count
    assert nokogiri_versions.all?(&:approved?)
  end

  test "import_from_csv skips existing versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0", status: :blocked)

    csv_data = <<~CSV
      name,version,platform
      rails,7.0.0,ruby
      rails,7.1.0,ruby
    CSV

    count = BaselineService.import_from_csv(csv_data)

    assert_equal 2, count
    assert_equal 2, GemVersion.count

    # Original blocked version should stay blocked
    original = GemVersion.find_by(version: "7.0.0")
    assert original.blocked?

    # New version should be approved
    new_version = GemVersion.find_by(version: "7.1.0")
    assert new_version.approved?
  end

  test "import_from_gzipped_csv decompresses and imports" do
    csv_data = <<~CSV
      name,version,platform
      puma,6.0.0,ruby
    CSV

    gzipped = gzip_data(csv_data)
    count = BaselineService.import_from_gzipped_csv(gzipped)

    assert_equal 1, count
    assert GemPackage.exists?(name: "puma")
  end

  test "baseline_imported? returns false by default" do
    refute BaselineService.baseline_imported?
  end

  test "mark_baseline_imported! sets timestamp" do
    refute BaselineService.baseline_imported?

    BaselineService.mark_baseline_imported!

    assert BaselineService.baseline_imported?
    assert Setting.baseline_imported_at.present?
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
    File.delete(output_path) if File.exist?(output_path)
  end

  private

  def gzip_data(data)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(data)
    gz.close
    io.string
  end

  def build_gzipped_specs(specs)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    io.string
  end
end
