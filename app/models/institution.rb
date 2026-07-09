class Institution < ApplicationRecord
  enum institution_type: {
    amc: 0,
    broker: 1,
    government: 2,
    bank: 3,
    retirement: 4,
    other: 9
  }

  has_many :investment_accounts, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :institution_type, presence: true

  def to_s
    name
  end
end
