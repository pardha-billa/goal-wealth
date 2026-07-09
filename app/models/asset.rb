class Asset < ApplicationRecord
  enum asset_type: {
    mutual_fund: 0,
    etf: 1,
    ppf: 2,
    stock: 3,
    epf: 4,
    nps: 5,
    fd: 6,
    other: 9
  }

  enum asset_category: {
    equity: 0,
    debt: 1,
    hybrid: 2,
    gold: 3,
    international: 4,
    cash: 5,
    other: 6
  }, _prefix: true

  enum plan: {
    direct: 0,
    regular: 1
  }, _prefix: true

  enum option: {
    growth: 0,
    idcw: 1,
    dividend: 2
  }, _prefix: true

  belongs_to :investment_account
  has_one :investor, through: :investment_account
  has_one :institution, through: :investment_account
  has_many :transactions, dependent: :restrict_with_error
  has_many :price_histories, dependent: :restrict_with_error

  validates :asset_type, :code, :name, presence: true
  validates :code, uniqueness: { scope: [:investment_account_id, :asset_type] }

  def latest_price
    latest_price_history&.price
  end

  def latest_price_history
    if price_histories.loaded?
      price_histories.max_by(&:price_date)
    else
      price_histories.order(price_date: :desc).first
    end
  end

  def recent_price_histories(limit = 7)
    histories =
      if price_histories.loaded?
        price_histories.sort_by(&:price_date).reverse
      else
        price_histories.order(price_date: :desc).to_a
      end

    histories.first(limit)
  end

  def nav_history(limit = 7)
    recent_price_histories(limit).map do |history|
      {
        date: history.price_date,
        price: history.price.to_d
      }
    end
  end

  def latest_nav_change
    histories = recent_price_histories(2)
    return nil if histories.size < 2

    (histories[0].price.to_d - histories[1].price.to_d).round(4)
  end

  def latest_nav_change_pct
    histories = recent_price_histories(2)
    return nil if histories.size < 2

    previous_price = histories[1].price.to_d
    return nil if previous_price.zero?

    ((histories[0].price.to_d - previous_price) / previous_price * 100).round(2)
  end

  def nav_change_over(limit = 7)
    histories = recent_price_histories(limit)
    return nil if histories.size < 2

    latest_price = histories.first.price.to_d
    baseline_price = histories.last.price.to_d
    return nil if baseline_price.zero?

    absolute = (latest_price - baseline_price).round(4)
    percent = (absolute / baseline_price * 100).round(2)
    { absolute: absolute, percent: percent }
  end

  def display_name
    [name, code].compact.join(' - ')
  end

  def to_s
    account = investment_account ? "#{investment_account.institution&.name} #{investment_account.account_number}" : nil
    [display_name, account].compact.join(' @ ')
  end
end
