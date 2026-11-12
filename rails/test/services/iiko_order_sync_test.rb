require "test_helper"

class IikoOrderSyncTest < ActiveSupport::TestCase
  class Client
    attr_accessor :state, :responses
    attr_reader :calls
    def initialize(state)
      @state, @responses, @calls = state, [{ "orders" => [] }, { "orders" => [] }], []
    end
    def orders_by_table(org, table)
      @calls << [:read, org, table]
      responses.shift
    end
    def init_orders_by_table(org, group, table)
      @calls << [:init, org, group, table]
      { "correlationId" => "command" }
    end
    def command_status(org, correlation)
      @calls << [:status, org, correlation]
      { "state" => state }
    end
  end

  test "empty cloud catalog is refreshed from the configured POS table before no order" do
    client = Client.new("Success")
    result = adapter(client).load_bill("table")
    assert_equal :no_order, result.state
    assert_equal [[:read, "org", "table"], [:init, "org", "group", "table"], [:status, "org", "command"], [:read, "org", "table"]], client.calls
  end

  test "pending and failed sync are not reported as no order" do
    client = Client.new("InProgress")
    assert_equal :syncing, adapter(client).load_bill("table").state
    assert_equal 1, client.calls.count { |call| call.first == :read }
    assert_equal :unavailable, adapter(Client.new("Error")).load_bill("table").state
  end

  test "newly synchronized orders reach the mapper" do
    client = Client.new("Success")
    client.responses[1] = { "orders" => [{ "organizationId" => "org", "id" => "order", "creationStatus" => "InProgress" }] }
    assert_equal :syncing, adapter(client).load_bill("table").state
  end

  test "order locked by the cashier is syncing rather than absent" do
    client = Client.new("Error")
    client.define_singleton_method(:command_status) do |*|
      { "state" => "Error", "exception" => { "message" => "One or more objects used in edit session are already in use." } }
    end
    result = adapter(client).load_bill("table")
    assert_equal :syncing, result.state
    assert_includes result.reason, "редактируется в iikoFront"
  end

  private
  def adapter(client)
    Pos::Adapters::Iiko::Adapter.new(client: client, organization_id: "org", terminal_group_id: "group")
  end
end
