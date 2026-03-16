require "test_helper"
require "webmock/minitest"

class RubygemsClientTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "fetch_specs downloads specs file" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 200, body: "gzipped content")

    result = RubygemsClient.fetch_specs(:all)

    assert_equal "gzipped content", result
  end

  test "fetch_specs returns nil on failure" do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return(status: 500)

    result = RubygemsClient.fetch_specs(:all)

    assert_nil result
  end

  test "fetch_specs handles latest type" do
    stub_request(:get, "https://rubygems.org/latest_specs.4.8.gz")
      .to_return(status: 200, body: "latest content")

    result = RubygemsClient.fetch_specs(:latest)

    assert_equal "latest content", result
  end

  test "fetch_specs handles prerelease type" do
    stub_request(:get, "https://rubygems.org/prerelease_specs.4.8.gz")
      .to_return(status: 200, body: "prerelease content")

    result = RubygemsClient.fetch_specs(:prerelease)

    assert_equal "prerelease content", result
  end

  test "fetch_gem_info returns gem info" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/rails.json")
      .to_return(status: 200, body: '{"name": "rails", "version": "7.0.0"}')

    result = RubygemsClient.fetch_gem_info("rails")

    assert_equal({"name" => "rails", "version" => "7.0.0"}, result)
  end

  test "fetch_gem_info returns nil on failure" do
    stub_request(:get, "https://rubygems.org/api/v1/gems/nonexistent.json")
      .to_return(status: 404)

    result = RubygemsClient.fetch_gem_info("nonexistent")

    assert_nil result
  end

  test "fetch_dependencies downloads dependency payload" do
    payload = Marshal.dump([{"name" => "rails", "number" => "7.1.0"}])
    stub_request(:get, "https://rubygems.org/api/v1/dependencies")
      .with(query: {"gems" => "rails,nokogiri"})
      .to_return(status: 200, body: payload)

    result = RubygemsClient.fetch_dependencies(%w[rails nokogiri])

    assert_equal payload, result
  end

  test "parse_specs decompresses and unmarshals data" do
    # Create a valid gzipped marshal data
    specs = [["rails", Gem::Version.new("7.0.0"), "ruby"]]
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close
    gzipped_data = io.string

    result = RubygemsClient.parse_specs(gzipped_data)

    assert_equal 1, result.size
    assert_equal "rails", result.first[0]
  end

  test "parse_specs returns empty array for nil data" do
    result = RubygemsClient.parse_specs(nil)
    assert_equal [], result
  end

  test "parse_specs returns empty array for invalid data" do
    result = RubygemsClient.parse_specs("invalid gzip data")
    assert_equal [], result
  end

  test "parse_dependencies unmarshals marshal payload" do
    payload = Marshal.dump([{"name" => "rails", "number" => "7.1.0"}])

    result = RubygemsClient.parse_dependencies(payload)

    assert_equal "rails", result.first["name"]
  end

  test "download_file saves file to path" do
    stub_request(:get, "https://rubygems.org/gems/rails-7.0.0.gem")
      .to_return(status: 200, body: "gem content")

    path = Rails.root.join("tmp", "test_gem.gem")
    FileUtils.rm_f(path)

    result = RubygemsClient.download_file("https://rubygems.org/gems/rails-7.0.0.gem", path)

    assert result
    assert File.exist?(path)
    assert_equal "gem content", File.read(path)
  ensure
    FileUtils.rm_f(path)
  end

  test "download_file returns false on failure" do
    stub_request(:get, "https://rubygems.org/gems/nonexistent.gem")
      .to_return(status: 404)

    path = Rails.root.join("tmp", "test_gem.gem")

    result = RubygemsClient.download_file("https://rubygems.org/gems/nonexistent.gem", path)

    assert_not result
    assert_not File.exist?(path)
  end

  test "download_file cleans up partial file on error" do
    stub_request(:get, "https://rubygems.org/gems/error.gem")
      .to_raise(StandardError.new("connection error"))

    path = Rails.root.join("tmp", "test_gem.gem")

    result = RubygemsClient.download_file("https://rubygems.org/gems/error.gem", path)

    assert_not result
    assert_not File.exist?(path)
  end
end
