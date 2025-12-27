require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    setting = build(:setting)
    assert setting.valid?
  end

  test "requires key" do
    setting = build(:setting, key: nil)
    assert_not setting.valid?
    assert_includes setting.errors[:key], "can't be blank"
  end

  test "requires unique key" do
    create(:setting, key: "test_key")
    duplicate = build(:setting, key: "test_key")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "requires valid value_type" do
    setting = build(:setting, value_type: "invalid")
    assert_not setting.valid?
    assert_includes setting.errors[:value_type], "is not included in the list"
  end

  test "typed_value returns string for string type" do
    setting = build(:setting, value: "hello", value_type: "string")
    assert_equal "hello", setting.typed_value
  end

  test "typed_value returns integer for integer type" do
    setting = build(:setting, :integer, value: "42")
    assert_equal 42, setting.typed_value
  end

  test "typed_value returns boolean for boolean type" do
    setting = build(:setting, :boolean, value: "true")
    assert_equal true, setting.typed_value

    setting.value = "false"
    assert_equal false, setting.typed_value
  end

  test "typed_value returns parsed JSON for json type" do
    setting = build(:setting, :json, value: '{"key": "value"}')
    assert_equal({"key" => "value"}, setting.typed_value)
  end

  test "typed_value= converts to string" do
    setting = build(:setting, value_type: "string")
    setting.typed_value = "hello"
    assert_equal "hello", setting.value
  end

  test "typed_value= converts hash to JSON" do
    setting = build(:setting, value_type: "json")
    setting.typed_value = {key: "value"}
    assert_equal '{"key":"value"}', setting.value
  end

  test "get returns setting value" do
    create(:setting, key: "test_key", value: "test_value", value_type: "string")
    assert_equal "test_value", Setting.get("test_key")
  end

  test "get returns default when setting not found" do
    assert_equal 72, Setting.get("quarantine_hours")
  end

  test "set creates new setting" do
    Setting.set("new_key", "new_value")
    setting = Setting.find_by(key: "new_key")

    assert_not_nil setting
    assert_equal "new_value", setting.value
    assert_equal "string", setting.value_type
  end

  test "set updates existing setting" do
    create(:setting, key: "existing", value: "old", value_type: "string")
    Setting.set("existing", "new")

    setting = Setting.find_by(key: "existing")
    assert_equal "new", setting.value
  end

  test "set infers integer type" do
    Setting.set("count", 42)
    setting = Setting.find_by(key: "count")

    assert_equal "integer", setting.value_type
    assert_equal "42", setting.value
  end

  test "set infers boolean type" do
    Setting.set("enabled", true)
    setting = Setting.find_by(key: "enabled")

    assert_equal "boolean", setting.value_type
    assert_equal "true", setting.value
  end

  test "quarantine_hours returns default" do
    assert_equal 72, Setting.quarantine_hours
  end

  test "quarantine_hours returns configured value" do
    create(:setting, :quarantine_hours, value: "48")
    assert_equal 48, Setting.quarantine_hours
  end

  test "sync_interval_minutes returns default" do
    assert_equal 5, Setting.sync_interval_minutes
  end

  test "cache_gems? returns default" do
    assert_equal true, Setting.cache_gems?
  end

  test "upstream_source returns default" do
    assert_equal "https://rubygems.org", Setting.upstream_source
  end
end
