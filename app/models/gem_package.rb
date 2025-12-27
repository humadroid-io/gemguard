class GemPackage < ApplicationRecord
  has_many :versions, class_name: "GemVersion", dependent: :destroy
  has_many :quarantine_rules, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  scope :with_cached_versions, -> { joins(:versions).where.not(gem_versions: {cached_at: nil}).distinct }
  scope :tracked, -> { where.not(tracked_at: nil) }

  def track!
    update!(tracked_at: Time.current) if tracked_at.nil?
  end

  def tracked?
    tracked_at.present?
  end

  def latest_version
    versions.order(first_seen_at: :desc).first
  end

  def approved_versions
    versions.approved
  end

  def quarantined_versions
    versions.quarantined
  end
end
