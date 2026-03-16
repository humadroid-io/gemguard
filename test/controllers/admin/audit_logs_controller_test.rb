require "test_helper"

class Admin::AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @log = create(:audit_log, gem_name: "rails", version: "7.0.0", action: "download")
  end

  test "index returns success" do
    get admin_audit_logs_path
    assert_response :success
  end

  test "index displays audit logs" do
    get admin_audit_logs_path

    assert_select "td", text: /rails/
    assert_select "td", text: "7.0.0"
  end

  test "index filters by gem_name" do
    create(:audit_log, gem_name: "nokogiri", version: "1.0.0")

    get admin_audit_logs_path, params: {gem_name: "rails"}

    assert_response :success
    assert_select "td", text: /rails/
    assert_select "td", text: /nokogiri/, count: 0
  end

  test "index filters by action_type" do
    create(:audit_log, :spec_request)

    get admin_audit_logs_path, params: {action_type: "download"}

    assert_response :success
    assert_select ".badge", text: /Download/
    assert_select ".badge", text: /Spec Request/, count: 0
  end

  test "index filters by date range" do
    create(:audit_log, gem_name: "old-gem", requested_at: 1.week.ago)
    create(:audit_log, gem_name: "recent-gem", requested_at: Time.current)

    get admin_audit_logs_path, params: {
      date_from: Date.current.to_s,
      date_to: Date.current.to_s
    }

    assert_response :success
    assert_select "td", text: /recent-gem/
    assert_select "td", text: /old-gem/, count: 0
  end

  test "index paginates results" do
    55.times { |i| create(:audit_log, gem_name: "gem-#{i}") }

    get admin_audit_logs_path

    assert_response :success
    assert_select "nav.pagy"
  end

  test "export returns CSV" do
    get export_admin_audit_logs_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.content_type
    assert_includes response.body, "rails"
    assert_includes response.body, "7.0.0"
  end

  test "export filters by date range" do
    create(:audit_log, gem_name: "old-gem", requested_at: 1.week.ago)

    get export_admin_audit_logs_path(format: :csv), params: {
      date_from: Date.current.to_s
    }

    assert_response :success
    assert_includes response.body, "rails"
    assert_not_includes response.body, "old-gem"
  end

  test "export includes all columns" do
    get export_admin_audit_logs_path(format: :csv)

    assert_includes response.body, "Requested At"
    assert_includes response.body, "Action"
    assert_includes response.body, "Gem Name"
    assert_includes response.body, "Version"
    assert_includes response.body, "IP Address"
  end

  test "export does not HTML-escape quoted values" do
    create(:audit_log, gem_name: "quoted-gem", user_agent: 'bundler "quoted" agent')

    get export_admin_audit_logs_path(format: :csv)

    assert_response :success
    assert_includes response.body, 'bundler ""quoted"" agent'
    assert_not_includes response.body, "&quot;"
  end

  test "export does not include blank lines between rows" do
    create(:audit_log, gem_name: "nokogiri", version: "1.18.0")

    get export_admin_audit_logs_path(format: :csv)

    assert_response :success

    lines = response.body.lines
    assert_equal 3, lines.size
    refute lines.any? { |line| line.strip.empty? }
  end
end
