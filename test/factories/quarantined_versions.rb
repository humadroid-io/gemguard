FactoryBot.define do
  factory :quarantined_version do
    sequence(:name) { |n| "test-gem-#{n}" }
    sequence(:version) { |n| "#{n}.0.0" }
    platform { "ruby" }
    first_seen_at { 1.hour.ago }

    trait :active do
      first_seen_at { 1.hour.ago }
    end

    trait :expired do
      first_seen_at { 100.days.ago }
    end

    trait :java_platform do
      platform { "java" }
    end
  end
end
