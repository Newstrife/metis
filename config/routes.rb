Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :conversations, only: %i[index create show update] do
    collection do
      get :archived
    end
    member do
      post :cancel
      post :archive
      post :unarchive
      post :share
      delete :share, action: :unshare
    end
    resources :messages, only: :create
  end

  get "/share/:token", to: "shared_conversations#show", as: :shared_conversation

  get "/artifacts/:signed_id/preview",
      to: "artifact_previews#show", as: :artifact_preview

  # Account settings live behind a single /settings shell — profile,
  # connectors, and future sections (api keys, notifications, …) share
  # the same two-column layout. Helpers (`profile_path`,
  # `connectors_path`, …) keep their names; only URLs move under
  # /settings.
  scope "/settings", as: nil do
    resource :profile, only: %i[show update]
    post "profile/detect_timezone", to: "profiles#detect_timezone",
                                    as: :detect_timezone_profile
    resources :connectors, except: :show
    resources :skills, except: :show do
      member do
        post   "files",                   action: :add_file,      as: :add_file
        delete "files/:file_id",          action: :destroy_file,  as: :destroy_file
        get    "files/:file_id/download", action: :download_file, as: :download_file
      end
    end
  end
  get "/settings", to: redirect("/settings/profile")

  # Defines the root path route ("/")
  root "conversations#index"
end
