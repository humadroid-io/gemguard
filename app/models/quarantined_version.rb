class QuarantinedVersion < ApplicationRecord
  validates :name, presence: true
  validates :version, presence: true
  validates :platform, presence: true
  validates :first_seen_at, presence: true
  validates :version, uniqueness: {scope: [:name, :platform]}

  scope :active, -> { where("first_seen_at > ?", Setting.quarantine_period.ago) }
  scope :expired, -> { where("first_seen_at <= ?", Setting.quarantine_period.ago) }

  def self.quarantined?(name, version, platform = "ruby")
    active.exists?(name: name, version: version, platform: platform)
  end

  def expired?
    first_seen_at <= Setting.quarantine_period.ago
  end
end
