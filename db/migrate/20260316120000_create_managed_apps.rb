class CreateManagedApps < ActiveRecord::Migration[8.1]
  def change
    create_table :managed_apps do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :quarantine_hours
      t.boolean :cache_gems
      t.string :upstream_source

      t.timestamps
    end

    add_index :managed_apps, :name, unique: true
    add_index :managed_apps, :slug, unique: true
  end
end
