class CreateAcquiringConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :acquiring_connections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :merchant_id, null: false
      t.uuid :outlet_id, null: false
      t.string :provider, null: false, limit: 50
      t.string :name, null: false, limit: 100
      t.string :provider_merchant_id, null: false, limit: 64
      t.string :environment, null: false, default: "test", limit: 10
      t.binary :secret_ciphertext
      t.binary :secret_nonce
      t.integer :encryption_key_version
      t.boolean :is_default, null: false, default: false
      t.datetime :disabled_at
      t.timestamps
    end
    add_foreign_key :acquiring_connections, :merchants
    add_foreign_key :acquiring_connections, :merchant_outlets, column: [:outlet_id, :merchant_id], primary_key: [:id, :merchant_id]
    add_index :acquiring_connections, [:outlet_id, :provider, :environment, :provider_merchant_id], unique: true, name: "acquiring_outlet_account_unique"
    add_index :acquiring_connections, :outlet_id, unique: true, where: "is_default = TRUE", name: "acquiring_one_default_per_outlet"
    add_check_constraint :acquiring_connections, "environment IN ('test', 'live')", name: "acquiring_environment"
    add_check_constraint :acquiring_connections, "NOT is_default OR disabled_at IS NULL", name: "acquiring_default_not_disabled"
    add_check_constraint :acquiring_connections, "(secret_ciphertext IS NULL AND secret_nonce IS NULL AND encryption_key_version IS NULL) OR (octet_length(secret_ciphertext) > 16 AND octet_length(secret_nonce) = 12 AND encryption_key_version = 1 AND encryption_key_version IS NOT NULL AND secret_ciphertext IS NOT NULL AND secret_nonce IS NOT NULL)", name: "acquiring_secret_complete"
  end
end
