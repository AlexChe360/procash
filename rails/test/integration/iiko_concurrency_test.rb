require "test_helper"
require "timeout"

class IikoConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @merchant = Merchant.create!(legal_name: "Concurrent company", bin_iin: "987654321098")
    @user = User.create!(email: "race@example.test", password_hash: "unused", email_verified_at: Time.current)
    @membership = MerchantMembership.create!(merchant: @merchant, user: @user, role: "owner")
    @outlet = @merchant.merchant_outlets.create!(name: "Outlet", city: "Almaty", address: "Abay 10", pos_system: "iiko")
    @connection = @merchant.iiko_connections.create!(name: "iiko", api_key_ciphertext: "a" * 32, api_key_nonce: "b" * 12, status: "verified", last_verified_at: Time.current)
    @organization, @group = SecureRandom.uuid, SecureRandom.uuid
    @setting = OutletIikoSetting.create!(outlet_id: @outlet.id, merchant_id: @merchant.id, connection_id: @connection.id, organization_id: @organization, terminal_group_id: @group)
    @table = @outlet.outlet_tables.create!(code: "1", name: "Table 1", pos_table_id: SecureRandom.uuid)
    @started, @continue = Queue.new, Queue.new
    client = Object.new
    started, proceed, org, group = @started, @continue, @organization, @group
    client.define_singleton_method(:organizations) do
      started << true
      Timeout.timeout(10) { proceed.pop }
      [{ "id" => org }]
    end
    client.define_singleton_method(:terminal_groups) { |_| [{ "organizationId" => org, "items" => [{ "organizationId" => org, "id" => group }] }] }
    @factory = ->(_) { client }
  end

  teardown do
    @thread&.kill if @thread&.alive?
    @thread&.join
    OutletIikoActivationCheck.where(outlet_id: @outlet.id).delete_all
    OutletTable.where(outlet_id: @outlet.id).delete_all
    OutletIikoSetting.where(outlet_id: @outlet.id).delete_all
    IikoConnection.where(id: @connection.id).delete_all
    MerchantOutlet.where(id: @outlet.id).delete_all
    MerchantMembership.where(id: @membership.id).delete_all
    User.where(id: @user.id).delete_all
    Merchant.where(id: @merchant.id).delete_all
  end

  def start_activation
    @result = Queue.new
    @thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        service = Pos::Adapters::Iiko::Configuration.new(MerchantOutlet.find(@outlet.id), user: User.find(@user.id), client_factory: @factory)
        begin
          service.enable
          @result << :enabled
        rescue Pos::Adapters::Iiko::Configuration::Stale
          @result << :stale
        rescue => error
          @result << error
        end
      end
    end
    Timeout.timeout(10) { @started.pop }
  end

  def finish_activation
    @continue << true
    Timeout.timeout(10) { @thread.join }
    assert_equal :stale, @result.pop
    assert_not @setting.reload.is_enabled
  end

  test "concurrent table mutation invalidates snapshot without deadlock" do
    start_activation
    Timeout.timeout(10) { @table.update!(pos_table_id: SecureRandom.uuid) }
    finish_activation
  end

  test "concurrent credential mutation invalidates snapshot without deadlock" do
    start_activation
    Timeout.timeout(10) { @connection.update!(api_key_ciphertext: "c" * 32) }
    finish_activation
  end

  test "concurrent binding mutation invalidates snapshot without deadlock" do
    start_activation
    Timeout.timeout(10) { @setting.update!(terminal_group_id: SecureRandom.uuid) }
    finish_activation
  end
end
