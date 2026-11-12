require "test_helper"

class LegacyConstraintsTest < ActiveSupport::TestCase
  setup do
    @merchant = Merchant.create!(legal_name: "Company", bin_iin: "123456789012")
    @outlet = @merchant.merchant_outlets.create!(name: "Outlet", city: "Almaty", address: "Abay 10", pos_system: "iiko")
    @connection = @merchant.iiko_connections.create!(name: "iiko", api_key_ciphertext: "a" * 32, api_key_nonce: "b" * 12, status: "verified", last_verified_at: Time.current)
    @setting = OutletIikoSetting.create!(outlet_id: @outlet.id, merchant_id: @merchant.id, connection_id: @connection.id, organization_id: SecureRandom.uuid, terminal_group_id: SecureRandom.uuid)
    @table = @outlet.outlet_tables.create!(code: "1", name: "Table 1", pos_table_id: SecureRandom.uuid)
    @setting.update!(is_enabled: true)
    OutletIikoActivationCheck.create!(outlet_id: @outlet.id, status: "passed")
  end

  test "table change invalidates check increments revision and disables integration" do
    revision = @outlet.reload.iiko_config_revision
    @table.update!(pos_table_id: SecureRandom.uuid)
    assert_not @setting.reload.is_enabled
    assert_operator @outlet.reload.iiko_config_revision, :>, revision
    assert_not OutletIikoActivationCheck.exists?(outlet_id: @outlet.id)
  end

  test "connection changes disable linked integrations" do
    @connection.update!(status: "disabled")
    assert_not @setting.reload.is_enabled
    assert_not OutletIikoActivationCheck.exists?(outlet_id: @outlet.id)
  end

  test "binding changes cannot preserve activation" do
    @setting.update!(organization_id: SecureRandom.uuid)
    assert_not @setting.reload.is_enabled
  end

  test "cosmetic table changes preserve activation" do
    @table.update!(name: "New name")
    assert @setting.reload.is_enabled
    assert OutletIikoActivationCheck.exists?(outlet_id: @outlet.id)
  end
end
