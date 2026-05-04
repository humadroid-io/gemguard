require "test_helper"
require "webmock/minitest"

class CompactIndexServiceTest < ActiveSupport::TestCase
  include SpecsTestHelper

  parallelize(workers: 1)

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @service = CompactIndexService.new
    @storage_path = CompactIndexService.storage_path
    @legacy_specs_path = Rails.root.join("storage", "specs", "raw")
    FileUtils.rm_rf(@storage_path)
    FileUtils.rm_rf(@legacy_specs_path)

    @versions_content = <<~VERSIONS
      created_at: 2024-01-01T00:00:00Z
      ---
      rails 7.0.0,7.1.0,7.2.0 abc123
      nokogiri 1.15.0,1.16.0 def456
      evil-gem 1.0.0,2.0.0 ghi789
    VERSIONS

    @info_content = <<~INFO
      ---
      7.0.0 activesupport:= 7.0.0|checksum:abc
      7.1.0 activesupport:= 7.1.0|checksum:def
      7.2.0 activesupport:= 7.2.0|checksum:ghi
    INFO
  end

  teardown do
    FileUtils.rm_rf(@storage_path)
    FileUtils.rm_rf(@legacy_specs_path)
    WebMock.allow_net_connect!
  end

  test "sync_versions downloads and stores versions file" do
    stub_versions_request

    assert @service.sync_versions
    assert File.exist?(@storage_path.join("versions"))
  end

  test "sync_versions filters quarantined versions" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")
    stub_versions_request
    stub_info_request("rails")

    @service.sync_versions

    content = File.read(@storage_path.join("versions"))
    assert_includes content, "rails 7.0.0,7.2.0"
    assert_not_includes content, "7.1.0"
  end

  test "sync_versions preserves line endings when filtering versions" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")
    stub_versions_request
    stub_info_request("rails")

    @service.sync_versions

    content = File.read(@storage_path.join("versions"))
    assert_match(/^rails 7\.0\.0,7\.2\.0 [a-f0-9]+\nnokogiri /, content)
  end

  test "sync_versions quarantines newly appearing compact index versions before filtering" do
    FileUtils.mkdir_p(CompactIndexService.raw_storage_path)
    File.write(CompactIndexService.raw_storage_path.join("versions"), @versions_content.sub(",7.2.0", ""))
    stub_versions_request
    stub_info_request("rails")

    @service.sync_versions

    assert QuarantinedVersion.exists?(name: "rails", version: "7.2.0", platform: "ruby")

    content = File.read(@storage_path.join("versions"))
    assert_includes content, "rails 7.0.0,7.1.0"
    assert_not_includes content, "7.2.0"
  end

  test "sync_versions compares against legacy specs baseline when compact raw versions are missing" do
    FileUtils.mkdir_p(@legacy_specs_path)
    File.binwrite(@legacy_specs_path.join("specs.4.8.gz"), gzipped_specs([
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"]
    ]))
    stub_versions_request
    stub_info_request("rails")

    @service.sync_versions

    assert QuarantinedVersion.exists?(name: "rails", version: "7.2.0", platform: "ruby")

    content = File.read(@storage_path.join("versions"))
    assert_includes content, "rails 7.0.0,7.1.0"
    assert_not_includes content, "7.2.0"
  end

  test "sync_versions quarantines newly appearing platform versions before filtering" do
    FileUtils.mkdir_p(CompactIndexService.raw_storage_path)
    File.write(CompactIndexService.raw_storage_path.join("versions"), <<~VERSIONS)
      created_at: 2024-01-01T00:00:00Z
      ---
      nokogiri 1.16.0 def456
    VERSIONS
    @versions_content = <<~VERSIONS
      created_at: 2024-01-01T00:00:00Z
      ---
      nokogiri 1.16.0,1.16.0-x86_64-linux def456
    VERSIONS
    @info_content = <<~INFO
      ---
      1.16.0 |checksum:abc
      1.16.0-x86_64-linux |checksum:def
    INFO
    stub_versions_request
    stub_info_request("nokogiri")

    @service.sync_versions

    assert QuarantinedVersion.exists?(name: "nokogiri", version: "1.16.0", platform: "x86_64-linux")

    content = File.read(@storage_path.join("versions"))
    assert_includes content, "nokogiri 1.16.0"
    assert_not_includes content, "1.16.0-x86_64-linux"
  end

  test "sync_versions updates checksum to match filtered info content" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")
    stub_versions_request
    stub_info_request("rails")

    @service.sync_versions

    filtered_info = File.read(@storage_path.join("info", "rails"))
    expected_checksum = Digest::MD5.hexdigest(filtered_info)
    versions_line = File.read(@storage_path.join("versions")).lines.find { |line| line.start_with?("rails ") }

    assert_includes versions_line, expected_checksum
  end

  test "sync_versions removes gem line entirely if all versions quarantined" do
    create(:quarantined_version, name: "evil-gem", version: "1.0.0", platform: "ruby")
    create(:quarantined_version, name: "evil-gem", version: "2.0.0", platform: "ruby")
    stub_versions_request

    @service.sync_versions

    content = File.read(@storage_path.join("versions"))
    assert_not_includes content, "evil-gem"
  end

  test "sync_versions preserves header" do
    stub_versions_request

    @service.sync_versions

    content = File.read(@storage_path.join("versions"))
    assert_includes content, "created_at:"
    assert_includes content, "---"
  end

  test "sync_info downloads and stores info file" do
    stub_versions_request
    stub_info_request("rails")

    assert @service.sync_info("rails")
    assert File.exist?(@storage_path.join("info", "rails"))
  end

  test "sync_info filters quarantined versions" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")
    stub_versions_request
    stub_info_request("rails")

    @service.sync_info("rails")

    content = File.read(@storage_path.join("info", "rails"))
    assert_includes content, "7.0.0"
    assert_includes content, "7.2.0"
    assert_not_includes content, "7.1.0"
  end

  test "sync_versions filters blocked versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, :blocked, gem_package: gem_package, version: "7.1.0", platform: "ruby")
    stub_versions_request
    stub_info_request("rails")

    @service.sync_versions

    content = File.read(@storage_path.join("versions"))
    assert_includes content, "rails 7.0.0,7.2.0"
    assert_not_includes content, "7.1.0"
  end

  test "sync_info filters blocked versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, :blocked, gem_package: gem_package, version: "7.1.0", platform: "ruby")
    stub_versions_request
    stub_info_request("rails")

    @service.sync_info("rails")

    content = File.read(@storage_path.join("info", "rails"))
    assert_includes content, "7.0.0"
    assert_includes content, "7.2.0"
    assert_not_includes content, "7.1.0"
  end

  test "sync_info returns false for non-existent gem" do
    stub_versions_request
    stub_request(:get, "https://rubygems.org/info/nonexistent")
      .to_return(status: 404)

    assert_not @service.sync_info("nonexistent")
  end

  test "sync_names downloads and stores names file" do
    stub_names_request

    assert @service.sync_names
    assert File.exist?(@storage_path.join("names"))
  end

  test "sync_versions uses etag for conditional requests" do
    stub_versions_request
    @service.sync_versions

    # Second request with If-None-Match
    stub_request(:get, "https://rubygems.org/versions")
      .with(headers: {"If-None-Match" => "abc123"})
      .to_return(status: 304)

    assert @service.sync_versions
  end

  test "sync_versions returns false on network error" do
    stub_request(:get, "https://rubygems.org/versions")
      .to_timeout

    assert_not @service.sync_versions
  end

  private

  def stub_versions_request
    stub_request(:get, "https://rubygems.org/versions")
      .to_return(
        status: 200,
        body: @versions_content,
        headers: {"ETag" => "abc123"}
      )
  end

  def stub_info_request(gem_name)
    stub_request(:get, "https://rubygems.org/info/#{gem_name}")
      .to_return(
        status: 200,
        body: @info_content,
        headers: {"ETag" => "info123"}
      )
  end

  def stub_names_request
    stub_request(:get, "https://rubygems.org/names")
      .to_return(
        status: 200,
        body: "---\nrails\nnokogiri\n"
      )
  end
end
