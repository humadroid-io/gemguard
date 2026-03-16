class AppGemVersion < ApplicationRecord
  belongs_to :managed_app
  belongs_to :gem_version

  validates :gem_version_id, uniqueness: {scope: :managed_app_id}

  scope :direct, -> { where(direct: true) }

  delegate :gem_package, to: :gem_version
end
