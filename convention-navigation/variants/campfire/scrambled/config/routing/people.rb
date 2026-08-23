get "join/:join_code", to: "users#new", as: :join
post "join/:join_code", to: "users#create"

resources :qr_code, only: :show

resources :users, only: :show do
  scope module: "users" do
    resource :avatar, only: %i[ show destroy ]
    resource :ban, only: %i[ create destroy ]

    scope defaults: { user_id: "me" } do
      resource :sidebar, only: :show
      resource :profile
      resources :push_subscriptions do
        scope module: "push_subscriptions" do
          resources :test_notifications, only: :create
        end
      end
    end
  end
end

namespace :autocompletable do
  resources :users, only: :index
end

direct :fresh_user_avatar do |user, options|
  route_for :user_avatar, user.avatar_token, v: user.updated_at.to_fs(:number)
end
