class MasterDashboardSummary
  DEFAULT_CODES = %w[RET EDU Emergency SNET].freeze
  DISPLAY_NAMES = {
    'SNET' => 'Safety Net'
  }.freeze

  Snapshot = Struct.new(
    :goal,
    :code,
    :name,
    :current_value,
    :invested_amount,
    :absolute_return,
    :return_pct,
    :xirr_pct,
    :one_day_change,
    :one_day_change_pct,
    :target_amount,
    :target_date,
    :progress_pct,
    :remaining_to_target,
    :asset_count,
    :transaction_count,
    :children,
    keyword_init: true
  )

  ChildSnapshot = Struct.new(
    :goal,
    :code,
    :name,
    :current_value,
    :invested_amount,
    :absolute_return,
    :return_pct,
    :xirr_pct,
    :one_day_change,
    :one_day_change_pct,
    :asset_count,
    :transaction_count,
    keyword_init: true
  )

  def initialize(codes = DEFAULT_CODES)
    @codes = codes
  end

  def snapshots
    @snapshots ||= @codes.filter_map { |code| snapshot_for(FinancialGoal.find_by(code: code)) }
  end

  def total_current_value
    snapshots.sum(&:current_value)
  end

  def total_invested
    snapshots.sum(&:invested_amount)
  end

  def total_absolute_return
    total_current_value - total_invested
  end

  def total_return_pct
    return nil if total_invested.to_d.zero?

    (total_absolute_return / total_invested.to_d * 100).round(2)
  end

  def total_target_amount
    snapshots.sum { |snapshot| snapshot.target_amount.to_d }
  end

  def total_progress_pct
    return nil if total_target_amount.to_d.zero?

    (total_current_value / total_target_amount.to_d * 100).round(2)
  end

  def total_remaining_to_target
    return nil if total_target_amount.to_d.zero?

    (total_target_amount - total_current_value).round(2)
  end

  def total_asset_count
    snapshots.sum(&:asset_count)
  end

  def total_transaction_count
    snapshots.sum(&:transaction_count)
  end

  private

  def snapshot_for(goal)
    return nil unless goal

    children = component_goals(goal).map { |component_goal| child_snapshot_for(component_goal) }
    current_value = children.sum(&:current_value)
    invested_amount = children.sum(&:invested_amount)
    absolute_return = current_value - invested_amount
    target_amount = goal.target_amount
    one_day_change = children.any? { |child| child.one_day_change.present? } ? children.sum { |child| child.one_day_change.to_d }.round(2) : nil
    one_day_change_pct = aggregate_one_day_change_pct(children)

    Snapshot.new(
      goal: goal,
      code: goal.code,
      name: display_name(goal),
      current_value: current_value.round(2),
      invested_amount: invested_amount.round(2),
      absolute_return: absolute_return.round(2),
      return_pct: invested_amount.to_d.positive? ? (absolute_return / invested_amount.to_d * 100).round(2) : nil,
      xirr_pct: weighted_xirr_pct(children),
      one_day_change: one_day_change,
      one_day_change_pct: one_day_change_pct,
      target_amount: target_amount,
      target_date: goal.target_date,
      progress_pct: target_amount.to_d.positive? ? (current_value / target_amount.to_d * 100).round(2) : nil,
      remaining_to_target: target_amount.present? ? (target_amount.to_d - current_value).round(2) : nil,
      asset_count: children.sum(&:asset_count),
      transaction_count: children.sum(&:transaction_count),
      children: children
    )
  end

  def child_snapshot_for(goal)
    summary = PortfolioSummary.new(goal)

    ChildSnapshot.new(
      goal: goal,
      code: goal.code,
      name: display_name(goal),
      current_value: summary.current_value.round(2),
      invested_amount: summary.total_invested.round(2),
      absolute_return: summary.absolute_return.round(2),
      return_pct: summary.return_pct,
      xirr_pct: summary.xirr_pct,
      one_day_change: summary.one_day_portfolio_change,
      one_day_change_pct: summary.one_day_portfolio_change_pct,
      asset_count: summary.asset_count,
      transaction_count: summary.transaction_count
    )
  end

  def component_goals(goal)
    children = goal.child_goals.active.order(:id).to_a
    children.any? ? children : [goal]
  end

  def weighted_xirr_pct(children)
    eligible_children = children.select { |child| child.xirr_pct.present? && child.current_value.to_d.positive? }
    total_value = eligible_children.sum(&:current_value)
    return nil if total_value.to_d.zero?

    (eligible_children.sum { |child| child.xirr_pct.to_d * child.current_value.to_d } / total_value.to_d).round(2)
  end

  def aggregate_one_day_change_pct(children)
    current_total = 0.to_d
    previous_total = 0.to_d

    children.each do |child|
      next if child.one_day_change.blank?

      current_total += child.current_value.to_d
      previous_total += (child.current_value.to_d - child.one_day_change.to_d)
    end

    return nil if previous_total.zero?

    ((current_total - previous_total) / previous_total * 100).round(2)
  end

  def display_name(goal)
    DISPLAY_NAMES.fetch(goal.code, goal.name)
  end
end
