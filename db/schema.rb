# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_12_26_234033) do
  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.string "bundle_version"
    t.datetime "created_at", null: false
    t.string "gem_name", null: false
    t.string "ip_address"
    t.datetime "requested_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.string "version"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["gem_name"], name: "index_audit_logs_on_gem_name"
    t.index ["requested_at"], name: "index_audit_logs_on_requested_at"
  end

  create_table "gem_packages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "downloads_count"
    t.string "homepage_url"
    t.text "info"
    t.string "name"
    t.datetime "tracked_at"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_gem_packages_on_name", unique: true
    t.index ["tracked_at"], name: "index_gem_packages_on_tracked_at", where: "tracked_at IS NOT NULL"
  end

  create_table "gem_versions", force: :cascade do |t|
    t.datetime "cached_at"
    t.string "checksum"
    t.datetime "created_at", null: false
    t.integer "file_size"
    t.datetime "first_seen_at", null: false
    t.integer "gem_package_id", null: false
    t.string "platform", default: "ruby", null: false
    t.datetime "published_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["gem_package_id", "version", "platform"], name: "index_gem_versions_on_gem_package_id_and_version_and_platform", unique: true
    t.index ["gem_package_id"], name: "index_gem_versions_on_gem_package_id"
    t.index ["published_at"], name: "index_gem_versions_on_published_at"
    t.index ["status"], name: "index_gem_versions_on_status"
  end

  create_table "quarantine_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.integer "gem_package_id"
    t.integer "rule_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["enabled"], name: "index_quarantine_rules_on_enabled"
    t.index ["gem_package_id"], name: "index_quarantine_rules_on_gem_package_id"
    t.index ["rule_type"], name: "index_quarantine_rules_on_rule_type"
  end

  create_table "quarantined_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "first_seen_at", null: false
    t.string "name", null: false
    t.string "platform", default: "ruby", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["first_seen_at"], name: "index_quarantined_versions_on_first_seen_at"
    t.index ["name", "version", "platform"], name: "index_quarantined_versions_on_name_and_version_and_platform", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.string "value_type"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  add_foreign_key "gem_versions", "gem_packages"
  add_foreign_key "quarantine_rules", "gem_packages"
end
