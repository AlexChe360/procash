require "test_helper"
class LiveIikoTest < ActiveSupport::TestCase
  test "loads real QR bill through POS layer only when explicitly enabled" do
    skip "Manual only: set RUN_LIVE_IIKO_TEST=1 and dedicated staging credentials" unless ENV["RUN_LIVE_IIKO_TEST"] == "1"
    token = ENV.fetch("IIKO_TEST_QR_TOKEN")
    result = Pos::QrBillService.load(token)
    assert result, "Active QR table not found in dedicated test database"
    assert_not_equal :unavailable, result[:bill].state
    if result[:bill].state == :preview
      order = result[:bill].order
      assert_equal "KZT", order[:currency]
      assert_operator order[:total], :>=, 0
      assert_instance_of BigDecimal, order[:total]
      assert_operator order[:remaining], :>=, 0 if order[:remaining]
    end
  end
end
