class MarketOpportunitiesController < ApplicationController
  def show
    @analysis = MarketOpportunity::Analyzer.new.call
  end
end
