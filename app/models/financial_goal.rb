class FinancialGoal < ApplicationRecord
  enum status: {
    active: 0,
    archived: 1
  }

  belongs_to :parent_goal, class_name: 'FinancialGoal', optional: true
  has_many :child_goals, class_name: 'FinancialGoal', foreign_key: :parent_goal_id, dependent: :restrict_with_error
  has_many :transactions, dependent: :restrict_with_error

  validates :name, :code, presence: true
  validates :code, uniqueness: true

  def to_s
    code.present? ? "#{code} - #{name}" : name
  end
end
