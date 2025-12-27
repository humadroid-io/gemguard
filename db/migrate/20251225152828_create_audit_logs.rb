class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string :gem_name, null: false
      t.string :version
      t.string :action, null: false
      t.string :ip_address
      t.string :user_agent
      t.string :bundle_version
      t.datetime :requested_at, null: false

      t.timestamps
    end

    add_index :audit_logs, :gem_name
    add_index :audit_logs, :action
    add_index :audit_logs, :requested_at
  end
end
