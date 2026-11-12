require "test_helper"
class IikoSetupPresenterTest < ActiveSupport::TestCase
  test "saved organization with no tables points to step three rather than activation" do
    merchant = Merchant.create!(legal_name: "Cafe", bin_iin: "123456789012")
    outlet = merchant.merchant_outlets.create!(name: "Алма", city: "Алматы", address: "Абая 10", pos_system: "iiko")
    connection = merchant.iiko_connections.create!(name: "iiko", api_key_ciphertext: "a" * 32, api_key_nonce: "b" * 12, status: "verified", last_verified_at: Time.current)
    setting = OutletIikoSetting.create!(outlet_id: outlet.id, merchant_id: merchant.id, connection_id: connection.id, organization_id: SecureRandom.uuid, terminal_group_id: SecureRandom.uuid)
    wizard = IikoSetupPresenter.new(outlet.reload, tables: [])
    assert wizard.key_ready?
    assert wizard.binding_ready?
    assert_not wizard.tables_ready?
    assert_equal 3, wizard.current_step
    table = outlet.outlet_tables.create!(code: "1", name: "Стол 1", pos_table_id: SecureRandom.uuid)
    wizard = IikoSetupPresenter.new(outlet.reload, tables: [table])
    assert_equal 4, wizard.current_step
    assert wizard.tables_ready?
    assert_not wizard.enabled?
    setting.reload.update!(is_enabled: true)
    assert IikoSetupPresenter.new(outlet.reload, tables: [table]).enabled?
  end
  test "missing keys and unbound organizations have explicit steps" do
    merchant = Merchant.create!(legal_name: "Cafe", bin_iin: "123456789012")
    outlet = merchant.merchant_outlets.create!(name: "Алма", city: "Алматы", address: "Абая 10", pos_system: "iiko")
    assert_equal 1, IikoSetupPresenter.new(outlet, tables: []).current_step
    merchant.iiko_connections.create!(name: "iiko", api_key_ciphertext: "a" * 32, api_key_nonce: "b" * 12, status: "verified", last_verified_at: Time.current)
    assert_equal 2, IikoSetupPresenter.new(outlet.reload, tables: []).current_step
  end
end
