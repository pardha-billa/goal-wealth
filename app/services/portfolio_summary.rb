class PortfolioSummary
  CashFlow = Struct.new(:date, :amount)

  attr_reader :goal

  def initialize(goal)
    @goal = goal
  end

  def transactions
    @transactions ||= goal.transactions.includes(asset: [:price_histories, :investment_account]).order(:transaction_date, :created_at)
  end

  def holdings
    @holdings ||= begin
      rows = grouped_transactions.map do |asset, txs|
        units = holding_units(asset, txs)
        invested_amount = invested_amount_for_asset(asset, txs)
        capital_in = capital_in_for_asset(asset, txs)
        latest_price = latest_price_for_asset(asset, txs)
        nav_history = asset.nav_history(7)
        latest_nav_change = asset.latest_nav_change
        latest_nav_change_pct = asset.latest_nav_change_pct
        nav_change_over_7 = asset.nav_change_over(7)
        market_value = market_value_for_asset(asset, txs, units, latest_price)
        absolute_return = (market_value - invested_amount).round(2)
        return_pct = capital_in.to_d.zero? ? nil : (absolute_return / capital_in.to_d * 100).round(2)
        xirr_pct = xirr_pct_for_asset(asset, txs)

        {
          asset: asset,
          quantity: units,
          latest_price: latest_price&.round(4),
          nav_history: nav_history,
          latest_nav_change: latest_nav_change,
          latest_nav_change_pct: latest_nav_change_pct,
          nav_change_over_7: nav_change_over_7,
          market_value: market_value,
          invested_amount: invested_amount.round(2),
          capital_in: capital_in.round(2),
          absolute_return: absolute_return,
          return_pct: return_pct,
          xirr_pct: xirr_pct
        }
      end

      total_value = rows.sum { |holding| holding[:market_value] }
      rows.each do |holding|
        holding[:allocation_pct] = total_value.to_d.positive? ? (holding[:market_value] / total_value.to_d * 100).round(2) : 0
      end

      rows.sort_by { |holding| [holding[:xirr_pct].nil? ? 1 : 0, -(holding[:xirr_pct] || 0)] }
    end
  end

  def mutual_fund_nav_rows(limit = 7)
    holdings.select { |holding| holding[:asset].mutual_fund? }
            .sort_by { |holding| holding[:asset].name }
            .filter_map do |holding|
      history = holding[:nav_history].first(limit)
      next if history.empty?

      latest = history.first[:price]
      previous = history[1]&.dig(:price)
      baseline = history.last[:price]

      holding.merge(
        latest_nav: latest,
        one_day_change: previous ? (latest - previous).round(4) : nil,
        one_day_change_pct: previous.present? && previous.to_d.nonzero? ? (((latest - previous) / previous) * 100).round(2) : nil,
        seven_day_change: baseline ? (latest - baseline).round(4) : nil,
        seven_day_change_pct: baseline.present? && baseline.to_d.nonzero? ? (((latest - baseline) / baseline) * 100).round(2) : nil,
        nav_history: history
      )
    end
  end

  def total_invested
    holdings.sum { |holding| holding[:invested_amount] }
  end

  def current_value
    holdings.sum { |holding| holding[:market_value] }
  end

  def absolute_return
    current_value - total_invested
  end

  def return_pct
    return nil if total_capital_in.to_d.zero?

    (absolute_return / total_capital_in.to_d * 100).round(2)
  end

  def xirr_pct
    eligible_transactions = xirr_eligible_transactions
    return nil if eligible_transactions.empty?

    terminal_value = xirr_terminal_value
    flows = transaction_cash_flows(eligible_transactions)
    flows << CashFlow.new(Date.current, terminal_value.to_d) unless terminal_value.to_d.zero?
    compute_xirr(flows)
  end

  def xirr_pct_for_asset(asset, txs)
    return nil if txs.empty?

    units = holding_units(asset, txs)
    latest_price = latest_price_for_asset(asset, txs)
    current = market_value_for_asset(asset, txs, units, latest_price)

    flows = xirr_cash_flows_for_asset(asset, txs)
    flows << CashFlow.new(Date.current, current) unless current.to_d.zero?
    compute_xirr(flows)
  end

  def compute_xirr(flows)
    return nil unless flows.any? { |flow| flow.amount.positive? } && flows.any? { |flow| flow.amount.negative? }

    lower = -0.9999
    upper = 10.0
    value_lower = xirr_value(lower, flows)
    value_upper = xirr_value(upper, flows)
    return nil if value_lower.nil? || value_upper.nil? || value_lower * value_upper > 0

    rate = nil
    80.times do
      mid = (lower + upper) / 2.0
      value_mid = xirr_value(mid, flows)
      break if value_mid.nil?
      if value_mid.abs < 1.0e-8
        rate = mid
        break
      end

      if value_lower * value_mid <= 0
        upper = mid
        value_upper = value_mid
      else
        lower = mid
        value_lower = value_mid
      end
      rate = mid
    end

    return nil if rate.nil? || !rate.finite?
    (rate * 100).round(2)
  rescue StandardError
    nil
  end

  def xirr_value(rate, flows)
    base = 1 + rate
    return nil if base <= 0

    start_date = flows.map(&:date).min
    flows.sum do |flow|
      years = year_fraction(start_date, flow.date)
      flow.amount / base**years
    end
  end

  def category_breakdown
    groups = holdings.group_by { |holding| holding[:asset].asset_category }

    groups.map do |category, rows|
      value = rows.sum { |row| row[:market_value] }
      {
        asset_category: category,
        value: value.round(2),
        percentage: total_positive? ? (value / current_value * 100).round(2) : 0
      }
    end.sort_by { |row| -row[:value] }
  end

  def recent_transactions(limit = 6)
    transactions.last(limit).reverse
  end

  def total_money_in
    @total_money_in ||= transactions.sum { |transaction| money_in_transaction?(transaction) ? transaction.amount.to_d : 0.to_d }.round(2)
  end

  def total_money_out
    @total_money_out ||= transactions.sum { |transaction| money_out_transaction?(transaction) ? transaction.amount.to_d : 0.to_d }.round(2)
  end

  def net_cash_flow
    (total_money_in - total_money_out).round(2)
  end

  def one_day_portfolio_change
    one_day_portfolio_change_breakdown[:absolute]
  end

  def one_day_portfolio_change_pct
    one_day_portfolio_change_breakdown[:percent]
  end

  def total_capital_in
    @total_capital_in ||= holdings.sum { |holding| holding[:capital_in] }.round(2)
  end

  def target_progress_pct
    return nil if goal.target_amount.blank? || goal.target_amount.to_d.zero?

    (current_value / goal.target_amount.to_d * 100).round(2)
  end

  def remaining_to_target
    return nil if goal.target_amount.blank?

    (goal.target_amount.to_d - current_value).round(2)
  end

  def largest_holding
    holdings.max_by { |holding| holding[:market_value] }
  end

  def best_holding
    holdings.select { |holding| holding[:xirr_pct].present? }.max_by { |holding| holding[:xirr_pct] }
  end

  def weakest_holding
    holdings.select { |holding| holding[:xirr_pct].present? && !holding[:asset].asset_category_debt? }
            .min_by { |holding| holding[:xirr_pct] }
  end

  def top_holdings(limit = 5)
    holdings.sort_by { |holding| -holding[:market_value].to_d }.first(limit)
  end

  def profitable_holding_count
    holdings.count { |holding| holding[:absolute_return].to_d.positive? }
  end

  def loss_holding_count
    holdings.count { |holding| holding[:absolute_return].to_d.negative? }
  end

  def start_date
    transactions.minimum(:transaction_date)
  end

  def last_transaction_date
    transactions.maximum(:transaction_date)
  end

  def asset_count
    holdings.count
  end

  def transaction_count
    transactions.count
  end

  private

  def grouped_transactions
    transactions.group_by(&:asset)
  end

  def holding_units(asset, txs)
    return nil if balance_valued_asset?(asset, txs)

    txs.sum { |tx| tx.signed_units.to_d }
  end

  def latest_price_for_asset(asset, txs)
    return nil if balance_valued_asset?(asset, txs)

    asset.latest_price || txs.map(&:nav).compact.max&.to_d || 0.to_d
  end

  def invested_amount_for_asset(asset, txs)
    return ledger_principal(txs).round(2) if balance_valued_asset?(asset, txs)

    txs.sum { |tx| flow_amount(tx) }.round(2)
  end

  def capital_in_for_asset(asset, txs)
    return ledger_money_in(txs).round(2) if balance_valued_asset?(asset, txs)

    txs.sum { |tx| money_in_transaction?(tx) ? tx.amount.to_d : 0.to_d }.round(2)
  end

  def market_value_for_asset(asset, txs, units = holding_units(asset, txs), latest_price = latest_price_for_asset(asset, txs))
    return ledger_balance(txs).round(2) if balance_valued_asset?(asset, txs)

    (units.to_d * latest_price.to_d).round(2)
  end

  def balance_valued_asset?(asset, txs)
    return true if asset.ppf?
    return false if txs.any? { |tx| tx.nav.present? }

    asset.fd? || asset.epf? || asset.nps? || (asset.other? && asset.latest_price.blank?)
  end

  def ledger_money_in(txs)
    txs.sum { |tx| %w[buy deposit].include?(tx.transaction_type) ? tx.amount.to_d : 0.to_d }
  end

  def ledger_principal(txs)
    txs.sum do |tx|
      case tx.transaction_type
      when 'buy', 'deposit'
        tx.amount.to_d
      when 'sell', 'withdrawal'
        -tx.amount.to_d
      else
        0.to_d
      end
    end
  end

  def ledger_balance(txs)
    txs.sum do |tx|
      case tx.transaction_type
      when 'buy', 'deposit', 'interest'
        tx.amount.to_d
      when 'sell', 'withdrawal'
        -tx.amount.to_d
      else
        0.to_d
      end
    end
  end

  def xirr_cash_flows_for_asset(asset, txs)
    return ledger_xirr_cash_flows(txs) if balance_valued_asset?(asset, txs)

    txs.map { |tx| CashFlow.new(tx.transaction_date, xirr_cash_flow_amount(tx)) }
  end

  def ledger_xirr_cash_flows(txs)
    txs.filter_map do |tx|
      amount = case tx.transaction_type
               when 'buy', 'deposit'
                 -tx.amount.to_d
               when 'sell', 'withdrawal'
                 tx.amount.to_d
               end

      CashFlow.new(tx.transaction_date, amount) if amount
    end
  end

  def flow_amount(transaction)
    case transaction.transaction_type
    when 'sell', 'withdrawal'
      -transaction.amount.to_d
    else
      transaction.amount.to_d
    end
  end

  def money_in_transaction?(transaction)
    %w[buy deposit interest].include?(transaction.transaction_type)
  end

  def money_out_transaction?(transaction)
    %w[sell withdrawal].include?(transaction.transaction_type)
  end

  def transaction_cash_flows(source_transactions = transactions)
    source_transactions.map { |transaction| CashFlow.new(transaction.transaction_date, xirr_cash_flow_amount(transaction)) }
  end

  def xirr_cash_flow_amount(transaction)
    case transaction.transaction_type
    when 'sell', 'withdrawal'
      transaction.amount.to_d
    else
      -transaction.amount.to_d
    end
  end

  def cash_flows
    transaction_cash_flows + [CashFlow.new(Date.current, current_value.to_d)]
  end

  def xirr_eligible_transactions
    transactions.reject { |transaction| excluded_from_overall_xirr?(transaction.asset) }
  end

  def xirr_terminal_value
    holdings.reject { |holding| excluded_from_overall_xirr?(holding[:asset]) }
            .sum { |holding| holding[:market_value] }
            .round(2)
  end

  def excluded_from_overall_xirr?(asset)
    # PPF is manually maintained and should not influence aggregate money-weighted return.
    asset.ppf?
  end

  def year_fraction(start_date, end_date)
    (end_date - start_date).to_f / 365.25
  end

  def total_positive?
    current_value.positive?
  end

  def one_day_portfolio_change_breakdown
    @one_day_portfolio_change_breakdown ||= begin
      current_total = 0.to_d
      previous_total = 0.to_d
      tracked_holdings = 0

      grouped_transactions.each do |asset, txs|
        next if balance_valued_asset?(asset, txs)

        histories = asset.recent_price_histories(2)
        next if histories.size < 2

        units = holding_units(asset, txs)
        next if units.nil?

        latest_price = histories[0].price.to_d
        previous_price = histories[1].price.to_d

        current_total += units.to_d * latest_price
        previous_total += units.to_d * previous_price
        tracked_holdings += 1
      end

      absolute = (current_total - previous_total).round(2)
      percent = previous_total.positive? ? (absolute / previous_total * 100).round(2) : nil

      {
        absolute: tracked_holdings.positive? ? absolute : nil,
        percent: tracked_holdings.positive? ? percent : nil,
        tracked_holdings: tracked_holdings
      }
    end
  end
end
