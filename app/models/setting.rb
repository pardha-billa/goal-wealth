class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def to_s
    key
  end
end
