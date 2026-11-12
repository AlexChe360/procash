class OutletIikoSetting < ApplicationRecord
  self.table_name = "outlet_iiko_settings"
  self.primary_key = "outlet_id"
  belongs_to :merchant_outlet, foreign_key: :outlet_id
  belongs_to :iiko_connection, foreign_key: :connection_id, optional: true
end
