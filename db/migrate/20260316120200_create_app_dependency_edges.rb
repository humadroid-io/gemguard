class CreateAppDependencyEdges < ActiveRecord::Migration[8.1]
  def change
    create_table :app_dependency_edges do |t|
      t.references :managed_app, null: false, foreign_key: true
      t.references :parent_gem_version, foreign_key: {to_table: :gem_versions}
      t.references :child_gem_version, null: false, foreign_key: {to_table: :gem_versions}
      t.string :requirement

      t.timestamps
    end

    add_index :app_dependency_edges,
      [:managed_app_id, :parent_gem_version_id, :child_gem_version_id, :requirement],
      unique: true,
      name: "index_app_dependency_edges_uniqueness"
  end
end
