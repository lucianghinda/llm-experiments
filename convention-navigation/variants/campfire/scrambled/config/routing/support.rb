resources :searches, only: %i[ index create ] do
  delete :clear, on: :collection
end

resource :unfurl_link, only: :create

get "webmanifest"    => "pwa#manifest"
get "service-worker" => "pwa#service_worker"

get "up" => "rails/health#show", as: :rails_health_check
