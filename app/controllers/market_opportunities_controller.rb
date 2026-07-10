class MarketOpportunitiesController < ApplicationController
  def show
    @analysis = MarketOpportunity::Analyzer.new.call
  rescue StandardError => e
    Rails.logger.error("[MarketOpportunitiesController] #{e.class}: #{e.message}")
    @analysis = {
      inputs: {},
      sources: {},
      segments: {},
      ranked_segments: [],
      overall: {
        headline: "Overall Market Condition: Unavailable",
        condition_label: "Unavailable",
        score: nil,
        where_attractive_now: "Market data is unavailable right now.",
        overall_summary: "The market view could not be built from live sources.",
        data_source_note: "A source or runtime error blocked analysis.",
        market_bias: "Unavailable",
        deployment_note: "Try again after the source data issue is resolved.",
        valuation_percentile: nil,
        earnings_growth: nil,
        momentum_score: nil,
        top_segment: nil
      },
      checklist: [],
      deployment: {
        method: "Unavailable",
        rationale: "No deployment view could be generated.",
        schedule: []
      }
    }
  end
end
