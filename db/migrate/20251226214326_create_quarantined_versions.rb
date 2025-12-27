class CreateQuarantinedVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :quarantined_versions do |t|
      t.string :name, null: false
      t.string :version, null: false
      t.string :platform, null: false, default: "ruby"
      t.datetime :first_seen_at, null: false

      t.timestamps
    end

    add_index :quarantined_versions, [:name, :version, :platform], unique: true
    add_index :quarantined_versions, :first_seen_at
  end
end
