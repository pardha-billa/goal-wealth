class PortfoliosController < ApplicationController
  def show
    lookup_identifier = params[:goal_identifier].to_s.strip
    @goal = FinancialGoal.find_by(code: lookup_identifier) ||
            FinancialGoal.find_by('LOWER(name) = ?', lookup_identifier.downcase) ||
            FinancialGoal.find_by('LOWER(code) = ?', lookup_identifier.downcase)

    return redirect_to root_path, alert: 'Portfolio not found.' unless @goal

    @summary = PortfolioSummary.new(@goal)
  end
end
