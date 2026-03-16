class CreateAppGemVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :app_gem_versions do |t|
      t.references :managed_app, null: false, foreign_key: true
      t.references :gem_version, null: false, foreign_key: true
      t.boolean :direct, null: false, default: false

      t.timestamps
    end

    add_index :app_gem_versions, [:managed_app_id, :gem_version_id], unique: true
    add_index :app_gem_versions, [:managed_app_id, :direct]
  end
end
