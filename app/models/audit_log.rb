class AuditLog < ApplicationRecord
  validates :gem_name, presence: true
  validates :action, presence: true
  validates :requested_at, presence: true

  scope :recent, -> { order(requested_at: :desc) }
  scope :for_gem, ->(name) { where(gem_name: name) }
  scope :downloads, -> { where(action: "download") }
  scope :spec_requests, -> { where(action: "spec_request") }

  def self.log_download(gem_name:, version:, request:)
    create!(
      gem_name: gem_name,
      version: version,
      action: "download",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      bundle_version: extract_bundler_version(request.user_agent),
      requested_at: Time.current
    )
  end

  def self.log_spec_request(request:, spec_type:)
    create!(
      gem_name: spec_type,
      action: "spec_request",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      bundle_version: extract_bundler_version(request.user_agent),
      requested_at: Time.current
    )
  end

  def self.log_gemspec_request(gem_name:, version:, request:)
    create!(
      gem_name: gem_name,
      version: version,
      action: "gemspec_request",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      bundle_version: extract_bundler_version(request.user_agent),
      requested_at: Time.current
    )
  end

  def self.extract_bundler_version(user_agent)
    return unless user_agent
    match = user_agent.match(/bundler\/(\d+\.\d+\.\d+)/)
    match[1] if match
  end
end
