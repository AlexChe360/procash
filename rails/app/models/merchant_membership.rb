class MerchantMembership < ApplicationRecord
  belongs_to :merchant
  belongs_to :user
  validates :role, inclusion: { in: %w[owner manager cashier staff] }
  def manages? = is_active && %w[owner manager].include?(role)
end
