class PriceHistory < ApplicationRecord
  belongs_to :asset

  scope :latest_first, -> { order(price_date: :desc) }
  scope :last_trading_days, ->(count = 7) { latest_first.limit(count) }

  validates :price_date, :price, presence: true
  validates :price, numericality: { greater_than: 0 }
  validates :price_date, uniqueness: { scope: :asset_id }

  def to_s
    "#{asset&.name} - #{price_date} - #{price}"
  end
end
