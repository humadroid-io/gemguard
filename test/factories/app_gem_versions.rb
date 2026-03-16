FactoryBot.define do
  factory :app_gem_version do
    association :managed_app
    association :gem_version
    direct { false }
  end
end
