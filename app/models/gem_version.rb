class GemVersion < ApplicationRecord
  belongs_to :gem_package

  enum :status, {quarantined: 0, approved: 1, blocked: 2}

  validates :version, presence: true
  validates :platform, presence: true
  validates :first_seen_at, presence: true
  validates :version, uniqueness: {scope: [:gem_package_id, :platform]}

  scope :cached, -> { where.not(cached_at: nil) }

  delegate :name, to: :gem_package, prefix: :gem

  def full_name
    (platform == "ruby") ? "#{gem_name}-#{version}" : "#{gem_name}-#{version}-#{platform}"
  end

  def gem_file_name
    "#{full_name}.gem"
  end

  def gemspec_file_name
    "#{full_name}.gemspec.rz"
  end

  def cached?
    cached_at.present?
  end

  def available?
    approved? || !actively_quarantined?
  end

  def actively_quarantined?
    return false unless quarantined?
    return false if published_at.nil?

    published_at > Setting.quarantine_period.ago
  end
end
