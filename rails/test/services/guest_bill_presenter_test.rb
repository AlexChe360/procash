require "test_helper"
class GuestBillPresenterTest < ActiveSupport::TestCase
  def result(order)
    { outlet: Struct.new(:name).new("Алма"), table: Struct.new(:name).new("Стол 5"), tips: GuestBillPresenter::Settings.new(is_enabled: true, percentages: [5,10,15], allow_custom_amount: true), bill: Pos::BillState.build(:preview, order: order) }
  end
  def order
    { order_number: "125", total: BigDecimal("12500.75"), remaining: BigDecimal("11000.50"), processed_payments: BigDecimal("1500.25"), waiter_name: "Дана", items: [{ name: "Кофе", quantity: BigDecimal("1.5"), total: BigDecimal("1200.5") }] }
  end
  test "formats money and preserves unknown remaining" do
    view = GuestBillPresenter.new(result(order.merge(remaining: nil, processed_payments: nil)))
    assert_equal "12 500,75", view.bill.total
    assert_equal "1,5", view.bill.items.first.quantity
    assert_nil view.bill.remaining
    assert_nil view.tips
    assert_raises(ArgumentError) { GuestBillPresenter.new(result(order.merge(remaining: nil)), percentage: 5) }
  end
  test "fully paid and zero bills are notices" do
    assert_nil GuestBillPresenter.new(result(order.merge(remaining: 0.to_d, processed_payments: order[:total]))).bill
    assert_nil GuestBillPresenter.new(result(order.merge(total: 0.to_d, remaining: 0.to_d, processed_payments: 0.to_d))).bill
  end
  test "tip selection calculates on remaining balance with exact rounding" do
    view = GuestBillPresenter.new(result(order), percentage: 10)
    assert_equal "1 100,05", view.tips.tip_amount
    assert_equal "12 100,55", view.tips.total_amount
    assert_raises(ArgumentError) { GuestBillPresenter.new(result(order), percentage: 20) }
    assert_equal "300,50", GuestBillPresenter.new(result(order), custom: "300,50").tips.tip_amount
  end
  test "ported guest template escapes data and never enables payments" do
    data = result(order.merge(waiter_name: "<script>bad</script>"))
    html = ApplicationController.render(template: "bills/show", layout: false, assigns: { result: data, display: GuestBillPresenter.new(data, percentage: 10) })
    document = Nokogiri::HTML(html)
    assert document.at_css("#payment-button").key?("disabled")
    assert_includes document.at_css("#payment-button").text, "12 100,55"
    assert_includes html, "&lt;script&gt;bad&lt;/script&gt;"
    assert_includes html, "1 500,25"
    assert_includes html, "1 200,50"
  end
end
