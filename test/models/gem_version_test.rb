require "test_helper"

class GemVersionTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    gem_version = build(:gem_version)
    assert gem_version.valid?
  end

  test "requires version" do
    gem_version = build(:gem_version, version: nil)
    assert_not gem_version.valid?
    assert_includes gem_version.errors[:version], "can't be blank"
  end

  test "requires platform" do
    gem_version = build(:gem_version, platform: nil)
    assert_not gem_version.valid?
    assert_includes gem_version.errors[:platform], "can't be blank"
  end

  test "requires first_seen_at" do
    gem_version = build(:gem_version, first_seen_at: nil)
    assert_not gem_version.valid?
    assert_includes gem_version.errors[:first_seen_at], "can't be blank"
  end

  test "requires unique version per gem_package and platform" do
    gem_package = create(:gem_package)
    create(:gem_version, gem_package: gem_package, version: "1.0.0", platform: "ruby")
    duplicate = build(:gem_version, gem_package: gem_package, version: "1.0.0", platform: "ruby")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version], "has already been taken"
  end

  test "allows same version with different platform" do
    gem_package = create(:gem_package)
    create(:gem_version, gem_package: gem_package, version: "1.0.0", platform: "ruby")
    java_version = build(:gem_version, gem_package: gem_package, version: "1.0.0", platform: "java")

    assert java_version.valid?
  end

  test "status enum values" do
    assert_equal 0, GemVersion.statuses[:quarantined]
    assert_equal 1, GemVersion.statuses[:approved]
    assert_equal 2, GemVersion.statuses[:blocked]
  end

  test "full_name for ruby platform" do
    gem_package = create(:gem_package, name: "rails")
    gem_version = create(:gem_version, gem_package: gem_package, version: "7.0.0", platform: "ruby")

    assert_equal "rails-7.0.0", gem_version.full_name
  end

  test "full_name for non-ruby platform" do
    gem_package = create(:gem_package, name: "nokogiri")
    gem_version = create(:gem_version, gem_package: gem_package, version: "1.15.0", platform: "x86_64-linux")

    assert_equal "nokogiri-1.15.0-x86_64-linux", gem_version.full_name
  end

  test "gem_file_name" do
    gem_package = create(:gem_package, name: "rails")
    gem_version = create(:gem_version, gem_package: gem_package, version: "7.0.0", platform: "ruby")

    assert_equal "rails-7.0.0.gem", gem_version.gem_file_name
  end

  test "gemspec_file_name" do
    gem_package = create(:gem_package, name: "rails")
    gem_version = create(:gem_version, gem_package: gem_package, version: "7.0.0", platform: "ruby")

    assert_equal "rails-7.0.0.gemspec.rz", gem_version.gemspec_file_name
  end

  test "cached? returns true when cached_at is set" do
    gem_version = build(:gem_version, :cached)
    assert gem_version.cached?
  end

  test "cached? returns false when cached_at is nil" do
    gem_version = build(:gem_version, cached_at: nil)
    assert_not gem_version.cached?
  end

  test "available? returns true for approved versions" do
    gem_version = build(:gem_version, :approved)
    assert gem_version.available?
  end

  test "available? returns true for expired quarantine" do
    gem_version = build(:gem_version, :expired_quarantine)
    assert gem_version.available?
  end

  test "available? returns false for actively quarantined versions" do
    gem_version = build(:gem_version, :quarantined)
    assert_not gem_version.available?
  end

  test "actively_quarantined? returns false for approved versions" do
    gem_version = build(:gem_version, :approved)
    assert_not gem_version.actively_quarantined?
  end

  test "actively_quarantined? returns false when published_at is old" do
    gem_version = build(:gem_version, status: :quarantined, published_at: 1.year.ago)
    assert_not gem_version.actively_quarantined?
  end

  test "actively_quarantined? returns true when recently published" do
    gem_version = build(:gem_version, status: :quarantined, published_at: 1.hour.ago)
    assert gem_version.actively_quarantined?
  end

  test "gem_name delegates to gem_package" do
    gem_package = create(:gem_package, name: "rails")
    gem_version = create(:gem_version, gem_package: gem_package)

    assert_equal "rails", gem_version.gem_name
  end

  test "cached scope returns versions with cached_at set" do
    cached = create(:gem_version, :cached)
    not_cached = create(:gem_version, cached_at: nil)

    result = GemVersion.cached
    assert_includes result, cached
    assert_not_includes result, not_cached
  end

  test "approved scope returns only approved versions" do
    approved = create(:gem_version, :approved)
    quarantined = create(:gem_version, :quarantined)
    blocked = create(:gem_version, :blocked)

    result = GemVersion.approved
    assert_includes result, approved
    assert_not_includes result, quarantined
    assert_not_includes result, blocked
  end
end
