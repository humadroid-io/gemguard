require "test_helper"

class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  test "show returns success" do
    get admin_settings_path
    assert_response :success
  end

  test "show displays current settings" do
    get admin_settings_path

    assert_select "input[name='quarantine_hours']"
    assert_select "input[name='cache_gems']"
    assert_select "input[name='upstream_source']"
  end

  test "show displays default values" do
    get admin_settings_path

    assert_select "input[name='quarantine_hours'][value='72']"
    assert_select "input[name='upstream_source'][value='https://rubygems.org']"
  end

  test "update changes quarantine_hours" do
    patch admin_settings_path, params: { quarantine_hours: 48 }

    assert_redirected_to admin_settings_path
    assert_equal 48, Setting.quarantine_hours
  end

  test "update changes cache_gems" do
    patch admin_settings_path, params: { cache_gems: "0" }

    assert_redirected_to admin_settings_path
    assert_not Setting.cache_gems?
  end

  test "update changes upstream_source" do
    patch admin_settings_path, params: { upstream_source: "https://custom.rubygems.org" }

    assert_redirected_to admin_settings_path
    assert_equal "https://custom.rubygems.org", Setting.upstream_source
  end

  test "update multiple settings at once" do
    patch admin_settings_path, params: {
      quarantine_hours: 96,
      cache_gems: "1",
      upstream_source: "https://mirror.rubygems.org"
    }

    assert_redirected_to admin_settings_path
    assert_equal 96, Setting.quarantine_hours
    assert Setting.cache_gems?
    assert_equal "https://mirror.rubygems.org", Setting.upstream_source
  end

  test "update sets flash notice" do
    patch admin_settings_path, params: { quarantine_hours: 24 }

    assert_redirected_to admin_settings_path
    follow_redirect!
    assert_select ".alert-success", text: /Settings updated/
  end

  test "update changes baseline_url" do
    patch admin_settings_path, params: { baseline_url: "https://custom.example.com/baseline.csv.gz" }

    assert_redirected_to admin_settings_path
    assert_equal "https://custom.example.com/baseline.csv.gz", Setting.baseline_url
  end

  test "show displays baseline section" do
    get admin_settings_path

    assert_select "input[name='baseline_url']"
  end

  test "show displays baseline not imported warning" do
    get admin_settings_path

    assert_select ".alert-warning", text: /Baseline Not Imported/
    assert_select "button", text: /Import from Specs/
    assert_select "button", text: /Import RubyGems Dump/
    assert_select "button", text: /Import CSV/
  end

  test "show displays baseline imported success when imported" do
    Setting.set(:baseline_imported_at, Time.current.iso8601)

    get admin_settings_path

    assert_select ".alert-success", text: /Baseline Imported/
    assert_select "button", text: /Import CSV Baseline/, count: 0
    assert_select "button", text: /Import RubyGems Dump/, count: 0
  end

  test "import_baseline enqueues CSV job by default" do
    assert_enqueued_with(job: ImportBaselineJob) do
      post import_baseline_admin_settings_path, params: { source: "csv" }
    end

    assert_redirected_to admin_settings_path
    follow_redirect!
    assert_select ".alert-success", text: /CSV baseline import started/
  end

  test "import_baseline enqueues RubyGems dump job when source is rubygems_dump" do
    assert_enqueued_with(job: ImportRubygemsDumpJob) do
      post import_baseline_admin_settings_path, params: { source: "rubygems_dump" }
    end

    assert_redirected_to admin_settings_path
    follow_redirect!
    assert_select ".alert-success", text: /RubyGems dump import started/
  end

  test "import_baseline rejects when baseline already imported" do
    Setting.set(:baseline_imported_at, Time.current.iso8601)

    assert_no_enqueued_jobs(only: ImportBaselineJob) do
      post import_baseline_admin_settings_path
    end

    assert_redirected_to admin_settings_path
    follow_redirect!
    assert_select ".alert-error", text: /already imported/
  end
end
