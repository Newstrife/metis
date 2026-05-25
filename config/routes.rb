Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resources :conversations, only: %i[index create show] do
    post :cancel, on: :member
    resources :messages, only: :create
  end

  resources :connectors, except: :show

  resource :profile, only: %i[show update]
  post "profile/detect_timezone", to: "profiles#detect_timezone",
                                  as: :detect_timezone_profile

  # Defines the root path route ("/")
  root "conversations#index"
end
