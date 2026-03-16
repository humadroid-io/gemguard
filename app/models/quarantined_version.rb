class QuarantinedVersion < ApplicationRecord
  validates :name, presence: true
  validates :version, presence: true
  validates :platform, presence: true
  validates :first_seen_at, presence: true
  validates :version, uniqueness: {scope: [:name, :platform]}

  # Regenerate filtered specs when quarantine changes
  after_commit :schedule_specs_regeneration, on: [:create, :destroy]
  after_commit :invalidate_compact_index_info, on: [:create, :destroy]

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
    # Legacy Marshal specs
    RegenerateFilteredSpecsJob.perform_later(type: :all)
    RegenerateFilteredSpecsJob.perform_later(type: :latest)
    RegenerateFilteredSpecsJob.perform_later(type: :prerelease)

    # Compact Index
    SyncCompactIndexJob.perform_later(type: :versions)
  end

  # Delete cached info file so it gets refreshed with updated filtering
  # This ensures approved versions appear immediately in bundler
  def invalidate_compact_index_info
    info_path = Rails.root.join("storage", "compact_index", "info", name)
    etag_path = "#{info_path}.etag"

    FileUtils.rm_f(info_path)
    FileUtils.rm_f(etag_path)

    Rails.logger.info("QuarantinedVersion: Invalidated compact index info for #{name}")
  end
end
