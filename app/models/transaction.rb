class Transaction < ApplicationRecord
  enum transaction_type: {
    buy: 0,
    sell: 1,
    deposit: 2,
    withdrawal: 3,
    interest: 4
  }

  belongs_to :asset
  belongs_to :financial_goal
  has_one :investment_account, through: :asset
  has_one :investor, through: :investment_account
  has_one :institution, through: :investment_account

  validates :transaction_type, :transaction_date, :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :nav, numericality: { greater_than: 0 }, allow_nil: true

  def units
    return nil if nav.blank? || nav.to_d.zero?
    amount.to_d / nav.to_d
  end

  def signed_units
    return nil if units.nil?
    sell? || withdrawal? ? -units : units
  end

  def to_s
    "#{transaction_date} #{transaction_type.upcase} #{asset&.name} #{amount}"
  end
end
