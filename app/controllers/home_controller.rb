class HomeController < ApplicationController
  layout 'embed', only: :embed

  skip_before_action :load_portfolio_links, only: %i[update_nav embed]
  skip_before_action :authenticate_user!, only: %i[index embed]
  after_action :allow_iframe_embedding, only: %i[index embed]

  def index
    @dashboard = @portfolio_link_dashboard || MasterDashboardSummary.new
    @last_nav_date = last_nav_date
  end

  def embed
    @dashboard = MasterDashboardSummary.new
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

  def allow_iframe_embedding
    response.headers.delete('X-Frame-Options')
  end
end
