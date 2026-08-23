root "welcome#show"

resource :first_run

resource :session do
  scope module: "sessions" do
    resources :transfers, only: %i[ show update ]
  end
end
