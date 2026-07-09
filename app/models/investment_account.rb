class InvestmentAccount < ApplicationRecord
  enum account_type: {
    mf_folio: 0,
    demat: 1,
    ppf: 2,
    epf: 3,
    nps: 4,
    fd: 5,
    other: 9
  }

  belongs_to :investor
  belongs_to :institution
  has_many :assets, dependent: :restrict_with_error

  validates :account_type, :account_number, presence: true
  validates :account_number, uniqueness: { scope: [:investor_id, :institution_id] }

  def display_name
    [investor&.name, institution&.name, account_type&.upcase, account_number, label.presence].compact.join(' - ')
  end

  def to_s
    display_name
  end
end
