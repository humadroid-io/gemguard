Rails.application.routes.draw do
  # RubyGems-compatible API endpoints (Bundler requires these)
  get "specs.4.8.gz", to: "api/specs#index", defaults: {format: :marshal}
  get "latest_specs.4.8.gz", to: "api/specs#latest", defaults: {format: :marshal}
  get "prerelease_specs.4.8.gz", to: "api/specs#prerelease", defaults: {format: :marshal}
  get "gems/:id", to: "api/gems#show", constraints: {id: /[^\/]+\.gem/}
  get "quick/Marshal.4.8/:id", to: "api/gemspecs#show", constraints: {id: /[^\/]+\.gemspec\.rz/}

  # Admin interface
  namespace :admin do
    root to: "dashboard#index"
    resources :gem_packages, only: [:index, :show] do
      member do
        post :refresh
        post "versions/:version_id/approve", action: :approve_version, as: :approve_version
        post "versions/:version_id/block", action: :block_version, as: :block_version
      end
    end
    resources :quarantined_versions, only: [:index, :destroy] do
      member do
        post :approve
        post :block
      end
      collection do
        post :approve_all_expired
      end
    end
    resources :quarantine_rules, except: [:show]
    resources :audit_logs, only: [:index] do
      collection do
        get :export
      end
    end
    resource :settings, only: [:show, :update] do
      post :import_baseline
    end
  end
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  # Health check
  get "up" => "rails/health#show", :as => :rails_health_check

  # Root
  root "admin/dashboard#index"
end
