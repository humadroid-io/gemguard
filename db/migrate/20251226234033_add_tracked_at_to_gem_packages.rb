class AddTrackedAtToGemPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :gem_packages, :tracked_at, :datetime
    add_index :gem_packages, :tracked_at, where: "tracked_at IS NOT NULL"
  end
end
