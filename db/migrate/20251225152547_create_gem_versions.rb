class CreateGemVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :gem_versions do |t|
      t.references :gem_package, null: false, foreign_key: true
      t.string :version, null: false
      t.string :platform, null: false, default: "ruby"
      t.string :checksum
      t.datetime :published_at
      t.datetime :first_seen_at, null: false
      t.integer :status, null: false, default: 0
      t.datetime :cached_at
      t.integer :file_size

      t.timestamps
    end

    add_index :gem_versions, [:gem_package_id, :version, :platform], unique: true
    add_index :gem_versions, :status
    add_index :gem_versions, :published_at
  end
end
