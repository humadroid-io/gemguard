class CreateGemPackages < ActiveRecord::Migration[8.1]
  def change
    create_table :gem_packages do |t|
      t.string :name
      t.integer :downloads_count
      t.text :info
      t.string :homepage_url

      t.timestamps
    end
    add_index :gem_packages, :name, unique: true
  end
end
