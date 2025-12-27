require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    audit_log = build(:audit_log)
    assert audit_log.valid?
  end

  test "requires gem_name" do
    audit_log = build(:audit_log, gem_name: nil)
    assert_not audit_log.valid?
    assert_includes audit_log.errors[:gem_name], "can't be blank"
  end

  test "requires action" do
    audit_log = build(:audit_log, action: nil)
    assert_not audit_log.valid?
    assert_includes audit_log.errors[:action], "can't be blank"
  end

  test "requires requested_at" do
    audit_log = build(:audit_log, requested_at: nil)
    assert_not audit_log.valid?
    assert_includes audit_log.errors[:requested_at], "can't be blank"
  end

  test "recent scope orders by requested_at desc" do
    old = create(:audit_log, :old)
    recent = create(:audit_log, :recent)

    result = AuditLog.recent
    assert_equal recent, result.first
    assert_equal old, result.last
  end

  test "for_gem scope filters by gem_name" do
    rails_log = create(:audit_log, gem_name: "rails")
    rack_log = create(:audit_log, gem_name: "rack")

    result = AuditLog.for_gem("rails")
    assert_includes result, rails_log
    assert_not_includes result, rack_log
  end

  test "downloads scope filters by action" do
    download = create(:audit_log, :download)
    spec_request = create(:audit_log, :spec_request)

    result = AuditLog.downloads
    assert_includes result, download
    assert_not_includes result, spec_request
  end

  test "spec_requests scope filters by action" do
    download = create(:audit_log, :download)
    spec_request = create(:audit_log, :spec_request)

    result = AuditLog.spec_requests
    assert_not_includes result, download
    assert_includes result, spec_request
  end

  test "extract_bundler_version extracts version from user agent" do
    user_agent = "bundler/2.5.0 rubygems/3.5.0 ruby/3.3.0"
    assert_equal "2.5.0", AuditLog.extract_bundler_version(user_agent)
  end

  test "extract_bundler_version returns nil for non-bundler user agent" do
    user_agent = "curl/8.0.0"
    assert_nil AuditLog.extract_bundler_version(user_agent)
  end

  test "extract_bundler_version returns nil for nil user agent" do
    assert_nil AuditLog.extract_bundler_version(nil)
  end
end
