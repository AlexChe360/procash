require "test_helper"

class IikoActivationTest < ActiveSupport::TestCase
  class FakeClient
    attr_accessor :on_organizations, :organizations_value, :groups_value, :sections_value
    def organizations
      on_organizations&.call
      organizations_value
    end
    def terminal_groups(_id) = groups_value
    def restaurant_sections(_id, revision: nil) = sections_value
  end

  setup do
    @merchant = Merchant.create!(legal_name: "Company", bin_iin: "123456789012")
    @user = User.create!(email: "owner@example.test", password_hash: "unused", email_verified_at: Time.current)
    @membership = MerchantMembership.create!(merchant: @merchant, user: @user, role: "owner")
    @outlet = @merchant.merchant_outlets.create!(name: "Outlet", city: "Almaty", address: "Abay 10", pos_system: "iiko")
    @connection = @merchant.iiko_connections.create!(name: "iiko", api_key_ciphertext: "a" * 32, api_key_nonce: "b" * 12, status: "verified", last_verified_at: Time.current)
    @organization, @group = SecureRandom.uuid, SecureRandom.uuid
    @setting = OutletIikoSetting.create!(outlet_id: @outlet.id, merchant_id: @merchant.id, connection_id: @connection.id, organization_id: @organization, terminal_group_id: @group)
    @table = @outlet.outlet_tables.create!(code: "1", name: "Table 1", pos_table_id: SecureRandom.uuid)
    @client = FakeClient.new
    @client.organizations_value = [{ "id" => @organization }]
    @client.groups_value = [{ "organizationId" => @organization, "items" => [{ "organizationId" => @organization, "id" => @group }] }]
    @service = Pos::Adapters::Iiko::Configuration.new(@outlet, user: @user, client_factory: ->(_) { @client })
  end

  test "check does not enable and enable always repeats verification" do
    assert @service.check
    assert_not @setting.reload.is_enabled
    assert_equal "draft", @outlet.reload.status
    assert_equal "passed", OutletIikoActivationCheck.find(@outlet.id).status
    @client.groups_value = []
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.enable }
    assert_not @setting.reload.is_enabled
    @client.groups_value = [{ "organizationId" => @organization, "items" => [{ "organizationId" => @organization, "id" => @group }] }]
    @service.enable
    assert @setting.reload.is_enabled
    assert_equal "active", @outlet.reload.status
  end

  test "disabled outlet cannot be activated through POS setup" do
    @outlet.update!(status: "disabled")
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.enable }
    assert_equal "disabled", @outlet.reload.status
    assert_not @setting.reload.is_enabled
  end

  test "changed table mapping during online check prevents activation" do
    @client.on_organizations = -> { @table.update!(pos_table_id: SecureRandom.uuid) }
    assert_raises(Pos::Adapters::Iiko::Configuration::Stale) { @service.enable }
    assert_not @setting.reload.is_enabled
  end

  test "changed connection secrets prevent stale activation" do
    @client.on_organizations = -> { @connection.update!(api_key_ciphertext: "c" * 32) }
    assert_raises(Pos::Adapters::Iiko::Configuration::Stale) { @service.enable }
    assert_not @setting.reload.is_enabled
  end

  test "revoked membership during network request prevents activation" do
    @client.on_organizations = -> { @membership.update!(is_active: false) }
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.enable }
    assert_not @setting.reload.is_enabled
  end

  test "organization group ownership and disabled connections are enforced" do
    @client.groups_value = [{ "organizationId" => SecureRandom.uuid, "items" => [{ "organizationId" => @organization, "id" => @group }] }]
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.enable }
    @connection.update!(status: "disabled")
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.enable }
  end

  test "catalog rejects duplicates and excludes deleted and foreign tables" do
    id = SecureRandom.uuid
    table = { "id" => id, "name" => "Table", "isDeleted" => false }
    section = { "id" => SecureRandom.uuid, "name" => "Main", "terminalGroupId" => @group, "tables" => [table] }
    assert_equal [id], @service.normalize_tables({ "restaurantSections" => [section] }, @group).map { |t| t["id"] }
    section["tables"] = [table, table]
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.normalize_tables({ "restaurantSections" => [section] }, @group) }
    section["tables"] = [table.merge("isDeleted" => true)]
    assert_empty @service.normalize_tables({ "restaurantSections" => [section] }, @group)
    section["terminalGroupId"] = SecureRandom.uuid
    assert_empty @service.normalize_tables({ "restaurantSections" => [section] }, @group)
  end
  test "linking uses fresh catalog preserves QR and disables activation" do
    target = SecureRandom.uuid
    @client.sections_value = { "restaurantSections" => [{ "id" => SecureRandom.uuid, "name" => "Main", "terminalGroupId" => @group, "tables" => [{ "id" => target, "name" => "Table", "isDeleted" => false }] }] }
    token = @table.qr_token
    @setting.update!(is_enabled: true)
    @service.link(@table.id, target)
    assert_equal target, @table.reload.pos_table_id
    assert_equal token, @table.qr_token
    assert_not @setting.reload.is_enabled
    assert_raises(Pos::Adapters::Iiko::Configuration::Error) { @service.link(@table.id, SecureRandom.uuid) }
  end

  test "catalog uses actual iiko numbers while preserving table identities and names" do
    sections = { "Бар" => (1..10), "Зал" => (11..30) }.map do |name, numbers|
      { "id" => SecureRandom.uuid, "name" => name, "terminalGroupId" => @group,
        "tables" => numbers.each_with_index.map { |number, index| { "id" => SecureRandom.uuid, "name" => "Стол #{index + 1}", "number" => number } }.reverse }
    end
    tables = @service.normalize_tables({ "restaurantSections" => sections }, @group)
    hall = tables.select { |table| table["sectionName"] == "Зал" }
    assert_equal (11..30).map { |number| "Стол #{number}" }, hall.map { |table| table["displayName"] }
    assert_equal "Стол 1", hall.first["name"]
    assert_equal sections.last["tables"].last["id"], hall.first["id"]
    assert_equal (1..10).to_a, tables.select { |table| table["sectionName"] == "Бар" }.map { |table| table["number"] }
    sections.first["tables"] = [{ "id" => SecureRandom.uuid, "name" => "Терраса", "number" => 42 }, { "id" => SecureRandom.uuid, "name" => "Стол 7" }]
    labels = @service.normalize_tables({ "restaurantSections" => sections.first(1) }, @group).map { |table| table["displayName"] }
    assert_equal ["Терраса · № 42", "Стол 7"], labels
  end

  test "catalog sorts table numbers naturally within each section" do
    sections = ["Зал 10", "Зал 2"].map do |name|
      { "id" => SecureRandom.uuid, "name" => name, "terminalGroupId" => @group,
        "tables" => [10, 2, 11, 1, 3].map { |number| { "id" => SecureRandom.uuid, "name" => "Стол #{number}", "isDeleted" => false } } }
    end
    tables = @service.normalize_tables({ "restaurantSections" => sections }, @group)
    assert_equal ["Зал 2", "Зал 10"], tables.map { |table| table["sectionName"] }.uniq
    tables.group_by { |table| table["sectionName"] }.each_value do |group|
      assert_equal ["Стол 1", "Стол 2", "Стол 3", "Стол 10", "Стол 11"], group.map { |table| table["name"] }
    end
  end

end
