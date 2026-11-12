class OutletTable < ApplicationRecord
  belongs_to :merchant_outlet, foreign_key: :outlet_id
  validates :code, length: { in: 1..32 }, uniqueness: { scope: :outlet_id, case_sensitive: false }
  validates :name, length: { in: 2..120 }
  scope :active, -> { where(is_active: true) }
end
