class AppDependencyEdge < ApplicationRecord
  belongs_to :managed_app
  belongs_to :parent_gem_version, class_name: "GemVersion", optional: true
  belongs_to :child_gem_version, class_name: "GemVersion"

  validates :child_gem_version_id, uniqueness: {
    scope: [:managed_app_id, :parent_gem_version_id, :requirement],
    message: "edge already exists for this app"
  }
end
