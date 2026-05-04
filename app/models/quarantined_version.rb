class QuarantinedVersion < ApplicationRecord
  validates :name, presence: true
  validates :version, presence: true
  validates :platform, presence: true
  validates :first_seen_at, presence: true
  validates :version, uniqueness: {scope: [:name, :platform]}

  # Resolver-visible metadata is derived from this table, so create/destroy
  # must trigger regeneration even when upstream data has not changed.
  after_commit :invalidate_resolver_metadata, on: [:create, :destroy]
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

  # Remove stale resolver metadata immediately; background jobs rebuild it.
  def invalidate_resolver_metadata
    ResolverMetadataInvalidator.invalidate!(gem_names: [name])
  end

  # Schedule specs regeneration via job.
  # Jobs are deduplicated to avoid multiple concurrent regenerations.
  def schedule_specs_regeneration
    # Legacy Marshal specs
    RegenerateFilteredSpecsJob.perform_later(type: :all)
    RegenerateFilteredSpecsJob.perform_later(type: :latest)
    RegenerateFilteredSpecsJob.perform_later(type: :prerelease)

    # Compact index /versions is another resolver entry point for bundler.
    SyncCompactIndexJob.perform_later(type: :versions)
  end

  # Delete cached info file so it gets refreshed with updated filtering
  # This ensures approved or blocked versions appear/disappear immediately when
  # bundler asks for /info/:name after a quarantine change.
  def invalidate_compact_index_info
    info_path = Rails.root.join("storage", "compact_index", "info", name)
    etag_path = "#{info_path}.etag"

    FileUtils.rm_f(info_path)
    FileUtils.rm_f(etag_path)

    Rails.logger.info("QuarantinedVersion: Invalidated compact index info for #{name}")
  end
end
