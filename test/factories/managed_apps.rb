FactoryBot.define do
  factory :managed_app do
    sequence(:name) { |n| "App #{n}" }
    sequence(:slug) { |n| "app-#{n}" }
    description { "Example application" }
  end
end
