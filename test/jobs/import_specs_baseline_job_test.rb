require "test_helper"
require "webmock/minitest"

class ImportSpecsBaselineJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    @specs_path = Rails.root.join("storage", "specs", "raw")
    FileUtils.rm_rf(@specs_path)

    Setting.set(:baseline_imported_at, nil)
  end

  teardown do
    WebMock.allow_net_connect!
    FileUtils.rm_rf(@specs_path)
  end

  test "imports specs and enqueues spec regeneration" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [])

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      ImportSpecsBaselineJob.perform_now
    end

    assert GemPackage.exists?(name: "rails")
  end

  test "passes include_prerelease option" do
    stub_specs(:all, [["rails", Gem::Version.new("7.0.0"), "ruby"]])
    stub_specs(:latest, [])
    stub_specs(:prerelease, [["rails", Gem::Version.new("8.0.0.beta1"), "ruby"]])

    ImportSpecsBaselineJob.perform_now(include_prerelease: true)

    assert GemVersion.exists?(version: "8.0.0.beta1")
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
