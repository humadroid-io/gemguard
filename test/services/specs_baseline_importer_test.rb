require "test_helper"
require "webmock/minitest"

class SpecsBaselineImporterTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @raw_specs_path = Rails.root.join("storage", "specs", "raw")
    @filtered_specs_path = Rails.root.join("storage", "specs")
    FileUtils.rm_rf(@raw_specs_path)
    FileUtils.rm_rf(@filtered_specs_path)

    # Clear any existing baseline
    Setting.set(:baseline_imported_at, nil)
    Setting.set(:baseline_source, nil)
  end

  teardown do
    WebMock.allow_net_connect!
    FileUtils.rm_rf(@raw_specs_path)
    FileUtils.rm_rf(@filtered_specs_path)
  end

  test "does NOT create database records" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"],
      ["rack", Gem::Version.new("2.0.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    assert_no_difference ["GemPackage.count", "GemVersion.count"] do
      SpecsBaselineImporter.import
    end
  end

  test "returns count of specs entries" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"],
      ["rack", Gem::Version.new("2.0.0"), "ruby"]
    ])
    stub_specs(:latest, [["rails", Gem::Version.new("7.1.0"), "ruby"]])
    stub_specs(:prerelease, [])

    count = SpecsBaselineImporter.import

    # Count is sum of all specs (not deduplicated)
    assert_equal 4, count
  end

  test "saves raw specs files" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    assert File.exist?(@raw_specs_path.join("specs.4.8.gz"))
    assert File.exist?(@raw_specs_path.join("latest_specs.4.8.gz"))
    assert File.exist?(@raw_specs_path.join("prerelease_specs.4.8.gz"))
  end

  test "saves filtered specs files (copy of raw for baseline)" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    # Filtered specs should exist (same as raw for baseline import)
    assert File.exist?(@filtered_specs_path.join("specs.4.8.gz"))
    assert File.exist?(@filtered_specs_path.join("latest_specs.4.8.gz"))
  end

  test "sets baseline settings after import" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    assert SpecsBaselineImporter.baseline_imported?
    assert_equal "specs", Setting.get(:baseline_source)
  end

  test "baseline_imported? returns true after import" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    refute SpecsBaselineImporter.baseline_imported?

    SpecsBaselineImporter.import

    assert SpecsBaselineImporter.baseline_imported?
  end

  test "includes prerelease when requested" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]])

    count = SpecsBaselineImporter.import(include_prerelease: true)

    # Should include prerelease in count
    assert_equal 2, count
    # Prerelease specs should be in filtered (not just raw)
    assert File.exist?(@filtered_specs_path.join("prerelease_specs.4.8.gz"))
  end

  test "saves prerelease to raw even when not included" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]])

    SpecsBaselineImporter.import(include_prerelease: false)

    # Prerelease raw specs should exist (for SyncSpecsJob to diff against)
    assert File.exist?(@raw_specs_path.join("prerelease_specs.4.8.gz"))
  end

  test "specs content is valid Marshal format" do
    specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["nokogiri", Gem::Version.new("1.16.0"), "x86_64-linux"]
    ]
    stub_specs(:all, specs)
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    # Read and verify specs
    path = @filtered_specs_path.join("specs.4.8.gz")
    data = File.binread(path)
    parsed = parse_gzipped_specs(data)

    assert_equal 2, parsed.size
    assert_equal "rails", parsed[0][0]
    assert_equal "nokogiri", parsed[1][0]
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

  def parse_gzipped_specs(data)
    gz = Zlib::GzipReader.new(StringIO.new(data))
    Marshal.load(gz.read)
  end
end
