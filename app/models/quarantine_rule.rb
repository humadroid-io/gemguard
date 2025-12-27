class QuarantineRule < ApplicationRecord
  belongs_to :gem_package, optional: true

  enum :rule_type, {time_based: 0, version_pattern: 1, manual: 2}

  validates :rule_type, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :global, -> { where(gem_package_id: nil) }
  scope :for_gem, ->(gem_package) { where(gem_package: gem_package).or(global) }

  def global?
    gem_package_id.nil?
  end

  def applies_to?(gem_version)
    return false unless enabled?
    return false if gem_package_id.present? && gem_package_id != gem_version.gem_package_id

    case rule_type
    when "time_based"
      gem_version.first_seen_at > value.to_i.hours.ago
    when "version_pattern"
      gem_version.version.match?(Regexp.new(value))
    when "manual"
      true
    end
  end
end
