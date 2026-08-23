resource :account do
  scope module: "accounts" do
    resources :users

    resources :bots do
      scope module: "bots" do
        resource :key, only: :update
      end
    end

    resource :join_code, only: :create
    resource :logo, only: %i[ show destroy ]
    resource :custom_styles, only: %i[ edit update ]
  end
end

direct :fresh_account_logo do |options|
  route_for :account_logo, v: Current.account&.updated_at&.to_fs(:number), size: options[:size]
end
