require "test_helper"

class QuarantinedVersionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "valid with required attributes" do
    qv = build(:quarantined_version)
    assert qv.valid?
  end

  test "requires name" do
    qv = build(:quarantined_version, name: nil)
    assert_not qv.valid?
    assert_includes qv.errors[:name], "can't be blank"
  end

  test "requires version" do
    qv = build(:quarantined_version, version: nil)
    assert_not qv.valid?
    assert_includes qv.errors[:version], "can't be blank"
  end

  test "requires platform" do
    qv = build(:quarantined_version, platform: nil)
    assert_not qv.valid?
    assert_includes qv.errors[:platform], "can't be blank"
  end

  test "requires first_seen_at" do
    qv = build(:quarantined_version, first_seen_at: nil)
    assert_not qv.valid?
    assert_includes qv.errors[:first_seen_at], "can't be blank"
  end

  test "requires unique version per name and platform" do
    create(:quarantined_version, name: "evil-gem", version: "1.0.0", platform: "ruby")
    duplicate = build(:quarantined_version, name: "evil-gem", version: "1.0.0", platform: "ruby")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version], "has already been taken"
  end

  test "allows same version with different platform" do
    create(:quarantined_version, name: "evil-gem", version: "1.0.0", platform: "ruby")
    java_version = build(:quarantined_version, name: "evil-gem", version: "1.0.0", platform: "java")

    assert java_version.valid?
  end

  test "quarantined? returns true for active quarantine" do
    create(:quarantined_version, name: "evil-gem", version: "1.0.0", first_seen_at: 1.hour.ago)

    assert QuarantinedVersion.quarantined?("evil-gem", "1.0.0", "ruby")
  end

  test "quarantined? returns false for expired quarantine" do
    create(:quarantined_version, name: "evil-gem", version: "1.0.0", first_seen_at: 1.year.ago)

    assert_not QuarantinedVersion.quarantined?("evil-gem", "1.0.0", "ruby")
  end

  test "quarantined? returns false for non-existent record" do
    assert_not QuarantinedVersion.quarantined?("nonexistent", "1.0.0", "ruby")
  end

  test "expired? returns true when past quarantine period" do
    qv = build(:quarantined_version, first_seen_at: 1.year.ago)
    assert qv.expired?
  end

  test "expired? returns false when within quarantine period" do
    qv = build(:quarantined_version, first_seen_at: 1.hour.ago)
    assert_not qv.expired?
  end

  test "active scope returns only non-expired quarantines" do
    active = create(:quarantined_version, first_seen_at: 1.hour.ago)
    expired = create(:quarantined_version, name: "old-gem", first_seen_at: 1.year.ago)

    result = QuarantinedVersion.active
    assert_includes result, active
    assert_not_includes result, expired
  end

  test "expired scope returns only expired quarantines" do
    active = create(:quarantined_version, first_seen_at: 1.hour.ago)
    expired = create(:quarantined_version, name: "old-gem", first_seen_at: 1.year.ago)

    result = QuarantinedVersion.expired
    assert_not_includes result, active
    assert_includes result, expired
  end

  test "creating quarantined_version enqueues spec regeneration jobs" do
    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      create(:quarantined_version)
    end
  end

  test "destroying quarantined_version enqueues spec regeneration jobs" do
    qv = create(:quarantined_version)

    assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
      qv.destroy!
    end
  end
end
