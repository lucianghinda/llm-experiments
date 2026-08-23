resources :rooms do
  resources :messages

  nested do
    scope path: ":bot_key", as: :bot, defaults: { format: :json } do
      resources :messages, controller: "messages/by_bots", only: %i[ index create update destroy ] do
        resources :boosts, controller: "messages/boosts/by_bots", only: %i[ create destroy ]
      end
    end
  end

  scope module: "rooms" do
    resource :refresh, only: :show
    resource :settings, only: :show
    resource :involvement, only: %i[ show update ]
  end

  get "@:message_id", to: "rooms#show", as: :at_message
end

namespace :rooms do
  resources :opens
  resources :closeds
  resources :directs
end
