require "test_helper"
require "webmock/minitest"

class SpecsBaselineImporterTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @specs_path = Rails.root.join("storage", "specs", "raw")
    FileUtils.rm_rf(@specs_path)

    # Clear any existing baseline
    Setting.set(:baseline_imported_at, nil)
    Setting.set(:baseline_source, nil)
  end

  teardown do
    WebMock.allow_net_connect!
    FileUtils.rm_rf(@specs_path)
  end

  test "imports gems from specs files" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"],
      ["rack", Gem::Version.new("2.0.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    count = SpecsBaselineImporter.import

    assert_equal 3, count
    assert_equal 2, GemPackage.count
    assert GemPackage.exists?(name: "rails")
    assert GemPackage.exists?(name: "rack")
    assert_equal 2, GemPackage.find_by(name: "rails").versions.count
  end

  test "creates versions as approved" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    version = GemVersion.first
    assert version.approved?
  end

  test "does not duplicate existing versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, gem_package: gem_package, version: "7.0.0", platform: "ruby")

    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    count = SpecsBaselineImporter.import

    assert_equal 1, count # Only new version
    assert_equal 2, gem_package.versions.count
  end

  test "imports prerelease versions when requested" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [
      ["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]
    ])

    count = SpecsBaselineImporter.import(include_prerelease: true)

    assert_equal 2, count
    assert GemVersion.exists?(version: "8.0.0.beta1")
  end

  test "does not import prereleases by default" do
    stub_specs(:all, [
      ["rails", Gem::Version.new("7.0.0"), "ruby"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [
      ["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]
    ])

    count = SpecsBaselineImporter.import(include_prerelease: false)

    assert_equal 1, count
    assert_not GemVersion.exists?(version: "8.0.0.beta1")
  end

  test "saves raw specs files" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    assert File.exist?(@specs_path.join("specs.4.8.gz"))
    assert File.exist?(@specs_path.join("latest_specs.4.8.gz"))
    assert File.exist?(@specs_path.join("prerelease_specs.4.8.gz"))
  end

  test "sets baseline settings after import" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    SpecsBaselineImporter.import

    assert Setting.baseline_imported?
    assert_equal "specs", Setting.get(:baseline_source)
  end

  test "handles different platforms" do
    stub_specs(:all, [
      ["nokogiri", Gem::Version.new("1.0.0"), "ruby"],
      ["nokogiri", Gem::Version.new("1.0.0"), "x86_64-linux"],
      ["nokogiri", Gem::Version.new("1.0.0"), "arm64-darwin"]
    ])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    count = SpecsBaselineImporter.import

    assert_equal 3, count
    gem_package = GemPackage.find_by(name: "nokogiri")
    assert_equal 3, gem_package.versions.count
    assert gem_package.versions.exists?(platform: "ruby")
    assert gem_package.versions.exists?(platform: "x86_64-linux")
    assert gem_package.versions.exists?(platform: "arm64-darwin")
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
