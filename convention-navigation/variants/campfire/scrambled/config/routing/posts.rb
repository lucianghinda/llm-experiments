resources :messages do
  scope module: "messages" do
    resources :boosts
  end
end
