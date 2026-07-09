class HomeController < ApplicationController
  skip_before_action :load_portfolio_links, only: :update_nav

  def index
    @dashboard = @portfolio_link_dashboard || MasterDashboardSummary.new
    @last_nav_date = last_nav_date
  end

  def update_nav
    result = NavUpdates::UpdateTodayNav.call
    redirect_to root_path, notice: "NAV update complete: #{result[:updated]} updated, #{result[:skipped]} skipped."
  rescue StandardError => e
    redirect_to root_path, alert: "NAV update failed: #{e.message}"
  end

  private

  def last_nav_date
    nav_asset_types = Asset.asset_types.values_at('mutual_fund', 'etf')
    PriceHistory.joins(:asset).where(assets: { asset_type: nav_asset_types }).maximum(:price_date)
  end
end
