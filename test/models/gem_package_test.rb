require "test_helper"

class GemPackageTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    gem_package = build(:gem_package)
    assert gem_package.valid?
  end

  test "requires name" do
    gem_package = build(:gem_package, name: nil)
    assert_not gem_package.valid?
    assert_includes gem_package.errors[:name], "can't be blank"
  end

  test "requires unique name" do
    create(:gem_package, name: "rails")
    duplicate = build(:gem_package, name: "rails")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "has many versions" do
    gem_package = create(:gem_package)
    version1 = create(:gem_version, gem_package: gem_package, version: "1.0.0")
    version2 = create(:gem_version, gem_package: gem_package, version: "2.0.0")

    assert_equal 2, gem_package.versions.count
    assert_includes gem_package.versions, version1
    assert_includes gem_package.versions, version2
  end

  test "has many quarantine_rules" do
    gem_package = create(:gem_package)
    rule = create(:quarantine_rule, gem_package: gem_package)

    assert_includes gem_package.quarantine_rules, rule
  end

  test "destroys versions when destroyed" do
    gem_package = create(:gem_package, :with_versions)
    assert_equal 2, GemVersion.count

    gem_package.destroy
    assert_equal 0, GemVersion.count
  end

  test "latest_version returns most recent by first_seen_at" do
    gem_package = create(:gem_package)
    create(:gem_version, gem_package: gem_package, version: "1.0.0", first_seen_at: 1.year.ago)
    new_version = create(:gem_version, gem_package: gem_package, version: "2.0.0", first_seen_at: 1.day.ago)

    assert_equal new_version, gem_package.latest_version
  end

  test "approved_versions returns only approved" do
    gem_package = create(:gem_package)
    approved = create(:gem_version, :approved, gem_package: gem_package)
    create(:gem_version, :quarantined, gem_package: gem_package)
    create(:gem_version, :blocked, gem_package: gem_package)

    assert_equal [approved], gem_package.approved_versions.to_a
  end

  test "quarantined_versions returns only quarantined" do
    gem_package = create(:gem_package)
    create(:gem_version, :approved, gem_package: gem_package)
    quarantined = create(:gem_version, :quarantined, gem_package: gem_package)

    assert_equal [quarantined], gem_package.quarantined_versions.to_a
  end

  test "with_cached_versions scope returns packages with cached versions" do
    gem_with_cache = create(:gem_package)
    create(:gem_version, :cached, gem_package: gem_with_cache)

    gem_without_cache = create(:gem_package)
    create(:gem_version, gem_package: gem_without_cache, cached_at: nil)

    result = GemPackage.with_cached_versions
    assert_includes result, gem_with_cache
    assert_not_includes result, gem_without_cache
  end

  test "tracked scope returns only packages with tracked_at set" do
    tracked_gem = create(:gem_package, tracked_at: Time.current)
    untracked_gem = create(:gem_package, tracked_at: nil)

    result = GemPackage.tracked
    assert_includes result, tracked_gem
    assert_not_includes result, untracked_gem
  end

  test "track! sets tracked_at for untracked gem" do
    gem_package = create(:gem_package, tracked_at: nil)
    assert_nil gem_package.tracked_at

    gem_package.track!
    gem_package.reload

    assert_not_nil gem_package.tracked_at
    assert gem_package.tracked?
  end

  test "track! does not update tracked_at if already tracked" do
    original_tracked_at = 1.week.ago
    gem_package = create(:gem_package, tracked_at: original_tracked_at)

    gem_package.track!
    gem_package.reload

    assert_in_delta original_tracked_at, gem_package.tracked_at, 1.second
  end

  test "tracked? returns false for untracked gem" do
    gem_package = build(:gem_package, tracked_at: nil)
    assert_not gem_package.tracked?
  end

  test "tracked? returns true for tracked gem" do
    gem_package = build(:gem_package, tracked_at: Time.current)
    assert gem_package.tracked?
  end
end
