class CreateQuarantineRules < ActiveRecord::Migration[8.1]
  def change
    create_table :quarantine_rules do |t|
      t.references :gem_package, null: true, foreign_key: true
      t.integer :rule_type, null: false, default: 0
      t.string :value
      t.boolean :enabled, null: false, default: true
      t.text :description

      t.timestamps
    end

    add_index :quarantine_rules, :rule_type
    add_index :quarantine_rules, :enabled
  end
end
