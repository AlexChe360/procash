class OutletTipSetting < ApplicationRecord
  self.table_name = "outlet_tip_settings"
  self.primary_key = "outlet_id"
  belongs_to :merchant_outlet, foreign_key: :outlet_id
end
