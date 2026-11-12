class AddQrLogoToMerchantOutlets < ActiveRecord::Migration[8.1]
  def change
    add_column :merchant_outlets, :qr_logo, :binary
  end
end
