require "test_helper"

class QuarantineRuleTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    rule = build(:quarantine_rule)
    assert rule.valid?
  end

  test "requires rule_type" do
    rule = build(:quarantine_rule, rule_type: nil)
    assert_not rule.valid?
  end

  test "allows optional gem_package for global rules" do
    rule = build(:quarantine_rule, gem_package: nil)
    assert rule.valid?
  end

  test "rule_type enum values" do
    assert_equal 0, QuarantineRule.rule_types[:time_based]
    assert_equal 1, QuarantineRule.rule_types[:version_pattern]
    assert_equal 2, QuarantineRule.rule_types[:manual]
  end

  test "global? returns true when gem_package_id is nil" do
    rule = build(:quarantine_rule, :global)
    assert rule.global?
  end

  test "global? returns false when gem_package is set" do
    gem_package = create(:gem_package)
    rule = build(:quarantine_rule, gem_package: gem_package)
    assert_not rule.global?
  end

  test "enabled scope returns only enabled rules" do
    enabled = create(:quarantine_rule, enabled: true)
    disabled = create(:quarantine_rule, :disabled)

    result = QuarantineRule.enabled
    assert_includes result, enabled
    assert_not_includes result, disabled
  end

  test "global scope returns rules without gem_package" do
    global = create(:quarantine_rule, :global)
    specific = create(:quarantine_rule, :for_gem)

    result = QuarantineRule.global
    assert_includes result, global
    assert_not_includes result, specific
  end

  test "for_gem scope returns global and gem-specific rules" do
    gem_package = create(:gem_package)
    global = create(:quarantine_rule, :global)
    specific = create(:quarantine_rule, gem_package: gem_package)
    other_gem = create(:quarantine_rule, :for_gem)

    result = QuarantineRule.for_gem(gem_package)
    assert_includes result, global
    assert_includes result, specific
    assert_not_includes result, other_gem
  end

  test "applies_to? returns false when disabled" do
    gem_version = create(:gem_version, :quarantined)
    rule = build(:quarantine_rule, :disabled)

    assert_not rule.applies_to?(gem_version)
  end

  test "applies_to? returns false for wrong gem_package" do
    other_gem = create(:gem_package)
    gem_version = create(:gem_version)
    rule = create(:quarantine_rule, gem_package: other_gem)

    assert_not rule.applies_to?(gem_version)
  end

  test "time_based rule applies when version is within time window" do
    gem_version = create(:gem_version, first_seen_at: 1.hour.ago)
    rule = create(:quarantine_rule, :time_based, value: "72")

    assert rule.applies_to?(gem_version)
  end

  test "time_based rule does not apply when version is older" do
    gem_version = create(:gem_version, first_seen_at: 100.hours.ago)
    rule = create(:quarantine_rule, :time_based, value: "72")

    assert_not rule.applies_to?(gem_version)
  end

  test "version_pattern rule applies when version matches" do
    gem_version = create(:gem_version, version: "0.1.0")
    rule = create(:quarantine_rule, :version_pattern, value: "^0\\.")

    assert rule.applies_to?(gem_version)
  end

  test "version_pattern rule does not apply when version doesn't match" do
    gem_version = create(:gem_version, version: "1.0.0")
    rule = create(:quarantine_rule, :version_pattern, value: "^0\\.")

    assert_not rule.applies_to?(gem_version)
  end

  test "manual rule always applies" do
    gem_version = create(:gem_version)
    rule = create(:quarantine_rule, :manual)

    assert rule.applies_to?(gem_version)
  end
end
