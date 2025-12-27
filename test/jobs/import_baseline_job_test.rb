# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class ImportBaselineJobTest < ActiveJob::TestCase
  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  teardown do
    WebMock.allow_net_connect!
  end

  test "performs import when baseline not imported" do
    csv_data = <<~CSV
      name,version,platform
      rails,7.0.0,ruby
    CSV

    gzipped = gzip_data(csv_data)

    stub_request(:get, Setting.baseline_url)
      .to_return(status: 200, body: gzipped)

    ImportBaselineJob.perform_now

    assert Setting.baseline_imported?
    assert GemPackage.exists?(name: "rails")
  end

  test "skips import when baseline already imported" do
    Setting.set(:baseline_imported_at, Time.current.iso8601)

    # Should not make any HTTP requests
    ImportBaselineJob.perform_now

    # No gem packages should be created
    assert_equal 0, GemPackage.count
  end

  test "enqueues spec regeneration after import" do
    csv_data = <<~CSV
      name,version,platform
      rails,7.0.0,ruby
    CSV

    gzipped = gzip_data(csv_data)

    stub_request(:get, Setting.baseline_url)
      .to_return(status: 200, body: gzipped)

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      ImportBaselineJob.perform_now
    end
  end

  private

  def gzip_data(data)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(data)
    gz.close
    io.string
  end
end
