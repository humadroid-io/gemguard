class QuarantinedVersion < ApplicationRecord
  validates :name, presence: true
  validates :version, presence: true
  validates :platform, presence: true
  validates :first_seen_at, presence: true
  validates :version, uniqueness: {scope: [:name, :platform]}

  # Regenerate filtered specs when quarantine changes
  after_commit :schedule_specs_regeneration, on: [:create, :destroy]

  scope :active, -> { where("first_seen_at > ?", Setting.quarantine_period.ago) }
  scope :expired, -> { where("first_seen_at <= ?", Setting.quarantine_period.ago) }

  def self.quarantined?(name, version, platform = "ruby")
    active.exists?(name: name, version: version, platform: platform)
  end

  def expired?
    first_seen_at <= Setting.quarantine_period.ago
  end

  private

  # Schedule specs regeneration via job
  # Jobs are deduplicated to avoid multiple concurrent regenerations
  def schedule_specs_regeneration
    RegenerateFilteredSpecsJob.perform_later(type: :all)
    RegenerateFilteredSpecsJob.perform_later(type: :latest)
    RegenerateFilteredSpecsJob.perform_later(type: :prerelease)
  end
end
