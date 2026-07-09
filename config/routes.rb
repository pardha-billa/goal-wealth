Rails.application.routes.draw do
  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'

  post 'dashboard/update-nav', to: 'home#update_nav', as: :update_dashboard_nav
  get 'portfolio/:goal_identifier', to: 'portfolios#show', as: :portfolio

  root 'home#index'
end
