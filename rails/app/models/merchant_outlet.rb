class MerchantOutlet < ApplicationRecord
  belongs_to :merchant
  has_many :outlet_tables, foreign_key: :outlet_id
  has_one :outlet_iiko_setting, foreign_key: :outlet_id
  has_one :outlet_tip_setting, foreign_key: :outlet_id
  has_many :acquiring_connections, foreign_key: :outlet_id
  has_many :acquiring_requests, foreign_key: :outlet_id
  validates :name, length: { in: 2..150 }
  validates :city, length: { in: 2..100 }
  validates :address, length: { minimum: 3 }
  validates :pos_system, inclusion: { in: %w[iiko r_keeper other] }, allow_nil: true
  validates :status, inclusion: { in: %w[draft active disabled] }
  def status_label
    { "draft" => "Настройка", "active" => "Активна", "disabled" => "Отключена" }.fetch(status, status)
  end
end
