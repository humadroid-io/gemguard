FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "setting_#{n}" }
    value { "test_value" }
    value_type { "string" }

    trait :integer do
      value_type { "integer" }
      value { "42" }
    end

    trait :boolean do
      value_type { "boolean" }
      value { "true" }
    end

    trait :json do
      value_type { "json" }
      value { '{"key": "value"}' }
    end

    trait :quarantine_hours do
      key { "quarantine_hours" }
      value { "72" }
      value_type { "integer" }
    end
  end
end
