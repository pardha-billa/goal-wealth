class Investor < ApplicationRecord
  has_many :investment_accounts, dependent: :restrict_with_error
  has_many :assets, through: :investment_accounts

  validates :name, presence: true, uniqueness: true

  def to_s
    name
  end
end
