require "bigdecimal"

module Pos::Adapters::Iiko
  class BillMapper
    def self.call(response, organization_id:, table_id:, currency: "KZT")
      new.prepare(response, organization_id, table_id, currency)
    end

    def prepare(response, organization_id, table_id, currency)
      orders = response.fetch("orders")
      raise ArgumentError unless orders.is_a?(Array)
      return state(:no_order) if orders.empty?
      return state(:multiple_orders) if orders.length != 1
      info = orders.first
      return unavailable("Организация заказа не совпадает") unless info["organizationId"] == organization_id
      return unavailable("Отсутствует идентификатор заказа") unless info["id"].is_a?(String) && !info["id"].strip.empty?
      return state(:syncing) if info["creationStatus"] == "InProgress"
      return unavailable("Заказ не прошёл синхронизацию") unless info["creationStatus"] == "Success"
      order = info["order"]
      return unavailable("Данные заказа отсутствуют") unless order.is_a?(Hash)
      return state(:closed) if order["status"] == "Closed"
      return unavailable("Заказ недоступен") unless %w[New Bill].include?(order["status"])
      return unavailable("Заказ не привязан к столу") unless order.fetch("tableIds", []).include?(table_id)
      total = decimal(order.fetch("sum"))
      return unavailable("Некорректная сумма заказа") if total.negative?
      paid = order["processedPaymentsSum"].nil? ? nil : decimal(order["processedPaymentsSum"])
      return unavailable("Противоречивые данные об оплатах") if paid && (paid.negative? || paid > total)
      items = order.fetch("items").filter_map do |item|
        next unless item["deleted"].nil?
        raise ArgumentError unless item["type"] == "Product"
        product = item.fetch("product")
        raise ArgumentError unless product["name"].is_a?(String) && product["id"].is_a?(String)
        quantity = decimal(item.fetch("amount"))
        decimal(item.fetch("price"))
        item_total = item["resultSum"].nil? ? nil : decimal(item["resultSum"])
        raise ArgumentError if quantity <= 0 || item_total&.negative?
        # Validate modifiers, matching Rust deserialization. Their amounts are already in resultSum.
        item["modifiers"]&.each do |modifier|
          raise ArgumentError unless modifier.dig("product", "name").is_a?(String) && modifier.dig("product", "id").is_a?(String)
          decimal(modifier.fetch("amount"))
          decimal(modifier["resultSum"]) unless modifier["resultSum"].nil?
        end
        { name: product["name"], quantity: quantity, total: item_total }
      end
      return unavailable("Состав заказа отсутствует") if items.empty? && total.positive?
      raise ArgumentError unless currency.match?(/\A[A-Z]{3}\z/)
      state(:preview, order: { external_order_id: info["id"], order_number: order["number"]&.to_s,
        status: order["status"] == "New" ? :open : :bill_presented, total: total, processed_payments: paid,
        remaining: paid.nil? ? nil : total - paid, currency: currency, items: items, waiter_name: order.dig("waiter", "name")&.strip&.presence })
    rescue KeyError, ArgumentError, TypeError, NoMethodError
      unavailable("Некорректный ответ кассовой системы")
    end

    private
    def decimal(value)
      raise ArgumentError if value.nil? || value.is_a?(Float)
      result = BigDecimal(value.to_s)
      raise ArgumentError unless result.finite? && result.abs <= Tips::Calculator::MAX
      result
    end
    def state(name, order: nil) = Pos::BillState.build(name, order: order)
    def unavailable(reason) = Pos::BillState.build(:unavailable, reason: reason)
  end
end
