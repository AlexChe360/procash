class GuestBillPresenter
  Item = Struct.new(:name, :quantity, :total, keyword_init: true)
  Bill = Struct.new(:number, :items, :total, :processed_payments, :remaining, :waiter_name, keyword_init: true)
  TipOption = Struct.new(:percentage, :selected, :tip_amount, :total_amount, keyword_init: true)
  TipView = Struct.new(:options, :selected_percentage, :tip_amount, :total_amount, :is_custom, :custom_input, keyword_init: true)
  Settings = Struct.new(:is_enabled, :percentages, :allow_custom_amount, keyword_init: true)
  attr_reader :bill, :tips, :notice_title, :notice_message, :tip_settings

  def initialize(result, percentage: 0, custom: nil)
    @tip_settings = result[:tips] || Settings.new(is_enabled: false, percentages: [5, 10, 15], allow_custom_amount: false)
    state = result[:bill]
    @tips = prepare_tips(state, percentage, custom)
    notices = {
      no_order: ["Счёт пока не открыт", "На этом столе пока нет открытого заказа."],
      syncing: ["Получаем счёт", "Кассовая система обновляет данные заказа."],
      multiple_orders: ["Несколько заказов", "Для оплаты обратитесь к сотруднику ресторана."],
      closed: ["Счёт закрыт", "Этот заказ уже закрыт в кассовой системе. Если требуется новый счёт, обратитесь к официанту."],
      unavailable: ["Оплата пока недоступна", "Попросите сотрудника ресторана помочь с оплатой."]
    }
    if state.state != :preview
      @notice_title, @notice_message = notices.fetch(state.state)
    elsif state.order[:total].zero?
      @notice_title, @notice_message = "Нет суммы к оплате", "По этому счёту отсутствует сумма к оплате."
    elsif state.order[:processed_payments] == state.order[:total]
      @notice_title, @notice_message = "Счёт оплачен", "По данным кассовой системы, этот счёт полностью оплачен."
    else
      order = state.order
      @bill = Bill.new(number: order[:order_number] || "—", total: money(order[:total]), processed_payments: order[:processed_payments] && money(order[:processed_payments]), remaining: order[:remaining] && money(order[:remaining]), waiter_name: order[:waiter_name], items: order[:items].map { |item| Item.new(name: item[:name], quantity: self.class.format_decimal(item[:quantity]), total: item[:total] && money(item[:total])) })
    end
  end

  def self.format_decimal(value, money: false)
    integer, fraction = value.to_s("F").split(".")
    fraction = fraction&.sub(/0+\z/, "")
    result = integer.reverse.scan(/.{1,3}/).join(" ").reverse
    result += ",#{money ? fraction.ljust(2, '0') : fraction}" if fraction.present?
    result
  end

  private
  def money(value) = self.class.format_decimal(value, money: true)
  def prepare_tips(state, percentage, custom)
    due = state.state == :preview ? state.order[:remaining] : nil
    unless @tip_settings.is_enabled && due
      raise ArgumentError, "Чаевые недоступны" unless percentage == 0 && custom.nil?
      return nil
    end
    calculator = Tips::Calculator.new(enabled: true, percentages: @tip_settings.percentages, custom: @tip_settings.allow_custom_amount)
    options = [0, *@tip_settings.percentages].map do |value|
      calculation = calculator.percentage(due, value)
      TipOption.new(percentage: value, selected: custom.nil? && value == percentage, tip_amount: money(calculation[:tip_amount]), total_amount: money(calculation[:total_amount]))
    end
    selected = custom.nil? ? calculator.percentage(due, percentage) : calculator.custom(due, custom)
    TipView.new(options: options, selected_percentage: percentage, tip_amount: money(selected[:tip_amount]), total_amount: money(selected[:total_amount]), is_custom: !custom.nil?, custom_input: custom || "")
  end
end
