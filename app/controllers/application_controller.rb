class ApplicationController < ActionController::Base
  before_action :load_portfolio_links

  private

  def load_portfolio_links
    @portfolio_link_dashboard = MasterDashboardSummary.new
    @portfolio_link_snapshots = @portfolio_link_dashboard.snapshots
  end
end
