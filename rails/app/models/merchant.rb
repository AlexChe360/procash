class Merchant < ApplicationRecord
  has_many :merchant_memberships
  has_many :merchant_outlets
  has_many :iiko_connections
  validates :legal_name, length: { in: 2..200 }
  validates :bin_iin, format: { with: /\A[0-9]{12}\z/ }, uniqueness: true
  validates :status, inclusion: { in: %w[draft active suspended] }
end
