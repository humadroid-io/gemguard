class ManagedApp < ApplicationRecord
  DEFAULT_SLUG = "default".freeze
  DEFAULT_NAME = "Default App".freeze

  has_many :app_gem_versions, dependent: :destroy
  has_many :gem_versions, through: :app_gem_versions
  has_many :app_dependency_edges, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :quarantine_hours, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 720}, allow_nil: true

  before_validation :ensure_slug

  scope :recently_updated, -> { order(updated_at: :desc) }

  def self.ensure_default!
    return first if exists?

    find_or_create_by!(slug: DEFAULT_SLUG) do |app|
      app.name = DEFAULT_NAME
      app.description = "Created automatically on first startup for the simplest initial setup."
    end
  end

  def effective_quarantine_hours
    quarantine_hours.presence || Setting.quarantine_hours
  end

  def effective_cache_gems
    cache_gems.nil? ? Setting.cache_gems? : cache_gems
  end

  def effective_upstream_source
    upstream_source.presence || Setting.upstream_source
  end

  def direct_gem_versions
    gem_versions.joins(:app_gem_versions).where(app_gem_versions: {managed_app_id: id, direct: true}).distinct
  end

  private

  def ensure_slug
    return if name.blank? && slug.blank?

    self.slug = (slug.presence || name).to_s.parameterize
  end
end
