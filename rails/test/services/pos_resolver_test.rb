require "test_helper"
class PosResolverTest < ActiveSupport::TestCase
  Reader = Struct.new(:kind) do
    def load_bill(_) = Pos::BillState.build(:no_order)
  end
  test "selects only matching unambiguous readers" do
    reader = Reader.new(:iiko)
    assert_equal reader, Pos::Resolver.resolve("iiko", [reader])
    [nil, "unknown", "r_keeper"].each do |kind|
      assert_raises(Pos::Resolver::Error) { Pos::Resolver.resolve(kind, [reader]) }
    end
    assert_raises(Pos::Resolver::Error) { Pos::Resolver.resolve("iiko", [reader, reader]) }
    assert_equal :r_keeper, Pos::Resolver.kind("rkeeper")
  end
  test "bill service validates tenant identifiers and POS before using reader" do
    reader = Reader.new(:iiko)
    context = { merchant_id: SecureRandom.uuid, outlet_id: SecureRandom.uuid, table_id: "table", configured_pos: "iiko" }
    assert_equal :no_order, Pos::BillService.load(reader, **context).state
    assert_raises(Pos::Resolver::Error) { Pos::BillService.load(reader, **context.merge(table_id: " ")) }
    assert_raises(Pos::Resolver::Error) { Pos::BillService.load(reader, **context.merge(configured_pos: "r_keeper")) }
    assert_raises(Pos::Resolver::Error) { Pos::BillService.load(reader, **context.merge(merchant_id: "00000000-0000-0000-0000-000000000000")) }
  end
end
