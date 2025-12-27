FactoryBot.define do
  factory :quarantine_rule do
    gem_package { nil }
    rule_type { :time_based }
    value { "72" }
    enabled { true }
    description { "Default 72-hour quarantine" }

    trait :disabled do
      enabled { false }
    end

    trait :global do
      gem_package { nil }
    end

    trait :time_based do
      rule_type { :time_based }
      value { "72" }
    end

    trait :version_pattern do
      rule_type { :version_pattern }
      value { "^0\\." }
      description { "Quarantine all 0.x versions" }
    end

    trait :manual do
      rule_type { :manual }
      value { nil }
      description { "Manually quarantined" }
    end

    trait :for_gem do
      association :gem_package
    end
  end
end
