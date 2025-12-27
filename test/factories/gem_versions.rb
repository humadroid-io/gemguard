FactoryBot.define do
  factory :gem_version do
    gem_package
    sequence(:version) { |n| "#{n}.0.0" }
    platform { "ruby" }
    checksum { SecureRandom.hex(32) }
    published_at { 1.year.ago }
    first_seen_at { 1.week.ago }
    status { :approved }
    cached_at { nil }
    file_size { nil }

    trait :quarantined do
      status { :quarantined }
      published_at { 1.hour.ago }
      first_seen_at { 1.hour.ago }
    end

    trait :approved do
      status { :approved }
      published_at { 1.year.ago }
      first_seen_at { 1.year.ago }
    end

    trait :blocked do
      status { :blocked }
    end

    trait :cached do
      cached_at { Time.current }
      file_size { 50_000 }
    end

    trait :java_platform do
      platform { "java" }
    end

    trait :expired_quarantine do
      status { :quarantined }
      published_at { 100.days.ago }
      first_seen_at { 100.days.ago }
    end
  end
end
