class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :load_portfolio_links, if: :user_signed_in?
  helper_method :current_user, :user_signed_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def user_signed_in?
    current_user.present?
  end

  def authenticate_user!
    return if user_signed_in?

    redirect_to new_session_path, alert: 'Please sign in to continue.'
  end

  def load_portfolio_links
    @portfolio_link_dashboard = MasterDashboardSummary.new
    @portfolio_link_snapshots = @portfolio_link_dashboard.snapshots
  end
end
