Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'

  get 'home', to: 'home#index', as: :home
  get 'embed/net-worth', to: 'home#embed', as: :embed_net_worth
  resource :market_opportunity, path: 'market-opportunity', only: :show
  root 'sessions#new'
  post 'dashboard/update-nav', to: 'home#update_nav', as: :update_dashboard_nav
  get 'portfolio/:goal_identifier', to: 'portfolios#show', as: :portfolio
end
