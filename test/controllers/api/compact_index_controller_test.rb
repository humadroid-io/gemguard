require "test_helper"
require "webmock/minitest"

class Api::CompactIndexControllerTest < ActionDispatch::IntegrationTest
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)

    @storage_path = Rails.root.join("storage", "compact_index")
    FileUtils.rm_rf(@storage_path)
    FileUtils.mkdir_p(@storage_path)
    FileUtils.mkdir_p(@storage_path.join("info"))

    @versions_content = <<~VERSIONS
      created_at: 2024-01-01T00:00:00Z
      ---
      rails 7.0.0,7.1.0 abc123
      nokogiri 1.15.0,1.16.0 def456
    VERSIONS

    @info_content = <<~INFO
      ---
      7.0.0 activesupport:= 7.0.0|checksum:abc123
      7.1.0 activesupport:= 7.1.0|checksum:def456
    INFO
  end

  teardown do
    FileUtils.rm_rf(@storage_path)
    WebMock.allow_net_connect!
  end

  test "versions returns versions file when available" do
    write_versions_file(@versions_content)

    get "/versions"

    assert_response :success
    assert_includes response.body, "rails"
  end

  test "versions sets cache headers" do
    write_versions_file(@versions_content)

    get "/versions"

    assert_response :success
    assert response.headers["ETag"].present?
    assert response.headers["Cache-Control"].present?
  end

  test "versions returns not_found when file missing and sync fails" do
    # Stub upstream to fail
    stub_request(:get, "https://rubygems.org/versions").to_return(status: 500)

    get "/versions"

    assert_response :not_found
  end

  test "versions syncs from upstream when file missing" do
    stub_request(:get, "https://rubygems.org/versions")
      .to_return(status: 200, body: @versions_content, headers: {"ETag" => "abc123"})

    get "/versions"

    assert_response :success
    assert_includes response.body, "rails"
    assert File.exist?(@storage_path.join("versions"))
  end

  test "info returns gem info when available" do
    write_info_file("rails", @info_content)

    get "/info/rails"

    assert_response :success
    assert_includes response.body, "7.0.0"
  end

  test "info sets cache headers" do
    write_info_file("rails", @info_content)

    get "/info/rails"

    assert_response :success
    assert response.headers["ETag"].present?
  end

  test "info syncs from upstream when file missing" do
    stub_request(:get, "https://rubygems.org/info/rails")
      .to_return(status: 200, body: @info_content, headers: {"ETag" => "info123"})

    get "/info/rails"

    assert_response :success
    assert_includes response.body, "7.0.0"
  end

  test "info returns not_found when sync fails" do
    stub_request(:get, "https://rubygems.org/info/unknown").to_return(status: 404)

    get "/info/unknown"

    assert_response :not_found
  end

  test "names returns names file when available" do
    write_file("names", "---\nrails\nnokogiri\n")

    get "/names"

    assert_response :success
    assert_includes response.body, "rails"
  end

  private

  def write_versions_file(content)
    write_file("versions", content)
  end

  def write_info_file(gem_name, content)
    path = @storage_path.join("info", gem_name)
    File.write(path, content)
  end

  def write_file(name, content)
    path = @storage_path.join(name)
    File.write(path, content)
  end
end
