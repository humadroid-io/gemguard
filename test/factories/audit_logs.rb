FactoryBot.define do
  factory :audit_log do
    sequence(:gem_name) { |n| "test-gem-#{n}" }
    version { "1.0.0" }
    action { "download" }
    ip_address { "127.0.0.1" }
    user_agent { "bundler/2.5.0 rubygems/3.5.0 ruby/3.3.0" }
    bundle_version { "2.5.0" }
    requested_at { Time.current }

    trait :download do
      action { "download" }
    end

    trait :spec_request do
      action { "spec_request" }
      gem_name { "specs.4.8.gz" }
      version { nil }
    end

    trait :recent do
      requested_at { 1.hour.ago }
    end

    trait :old do
      requested_at { 1.week.ago }
    end
  end
end
