require "test_helper"
class AdminActivityPresenterTest < ActiveSupport::TestCase
  test "daily totals use Almaty dates with zero filled days and bounded period" do
    today = Date.new(2026, 11, 12)
    Merchant.create!(legal_name: "Chart", bin_iin: "112233445566", created_at: Time.utc(2026, 11, 11, 20, 0))
    Merchant.create!(legal_name: "Older", bin_iin: "665544332211", created_at: Time.utc(2026, 11, 11, 18, 0))
    Merchant.create!(legal_name: "Excluded", bin_iin: "123123123123", created_at: Time.utc(2026, 10, 1))
    chart = AdminActivityPresenter.new(period: "7", today: today)
    assert_equal 7, chart.dates.size
    assert_equal [0, 0, 0, 0, 0, 1, 1], chart.companies
    assert_equal [0] * 7, chart.requests
    assert_equal 4, chart.ceiling
    assert_equal 934, chart.x(6)
    assert_equal 30, AdminActivityPresenter.new(period: "invalid", today: today).days
  end
end
