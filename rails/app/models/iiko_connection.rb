class IikoConnection < ApplicationRecord
  belongs_to :merchant
  def verified? = status == "verified" && last_verified_at.present?
end
