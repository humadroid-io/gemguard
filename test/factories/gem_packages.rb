FactoryBot.define do
  factory :gem_package do
    sequence(:name) { |n| "test-gem-#{n}" }
    downloads_count { 1000 }
    info { "A test gem for testing purposes" }
    homepage_url { "https://github.com/test/test-gem" }

    trait :with_versions do
      after(:create) do |gem_package|
        create(:gem_version, :approved, gem_package: gem_package, version: "1.0.0")
        create(:gem_version, :quarantined, gem_package: gem_package, version: "2.0.0")
      end
    end

    trait :popular do
      downloads_count { 1_000_000 }
    end
  end
end
