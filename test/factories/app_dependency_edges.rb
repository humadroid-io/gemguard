FactoryBot.define do
  factory :app_dependency_edge do
    association :managed_app
    association :child_gem_version, factory: :gem_version
    requirement { ">= 0" }
  end
end
