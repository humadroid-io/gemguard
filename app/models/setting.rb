class Setting < ApplicationRecord
  DEFAULTS = {
    "quarantine_hours" => 72,
    "sync_interval_minutes" => 5,
    "cache_gems" => true,
    "upstream_source" => "https://rubygems.org",
    "baseline_url" => "https://gemguard.example.com/baseline.csv.gz",
    "baseline_imported_at" => nil
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :value_type, inclusion: {in: %w[string integer boolean json]}

  def typed_value
    case value_type
    when "integer" then value.to_i
    when "boolean" then value == "true"
    when "json" then JSON.parse(value)
    else value
    end
  end

  def typed_value=(new_value)
    self.value = (new_value.is_a?(Hash) || new_value.is_a?(Array)) ? new_value.to_json : new_value.to_s
  end

  class << self
    def get(key)
      setting = find_by(key: key)
      setting ? setting.typed_value : DEFAULTS[key.to_s]
    end

    def set(key, value, value_type: nil)
      setting = find_or_initialize_by(key: key)
      setting.value_type = value_type || infer_type(value)
      setting.typed_value = value
      setting.save!
      setting.typed_value
    end

    def quarantine_hours
      get("quarantine_hours")
    end

    def quarantine_period
      quarantine_hours.hours
    end

    def sync_interval_minutes
      get("sync_interval_minutes")
    end

    def cache_gems?
      get("cache_gems")
    end

    def upstream_source
      get("upstream_source")
    end

    def baseline_url
      get("baseline_url")
    end

    def baseline_imported_at
      value = get("baseline_imported_at")
      value.present? ? Time.parse(value) : nil
    end

    def baseline_imported?
      baseline_imported_at.present?
    end

    private

    def infer_type(value)
      case value
      when Integer then "integer"
      when TrueClass, FalseClass then "boolean"
      when Hash, Array then "json"
      else "string"
      end
    end
  end
end
