module Pos::Adapters::Iiko
  class Adapter
    def initialize(client:, organization_id:, terminal_group_id: nil, currency: "KZT")
      @client, @organization_id, @currency = client, organization_id, currency
      @terminal_group_id = terminal_group_id
    end
    def kind = :iiko
    def load_bill(table_id)
      response = @client.orders_by_table(@organization_id, table_id)
      if response["orders"] == [] && @terminal_group_id.present?
        correlation = @client.init_orders_by_table(@organization_id, @terminal_group_id, table_id)["correlationId"]
        return Pos::BillState.build(:unavailable, reason: "Не удалось начать синхронизацию заказа") unless correlation.is_a?(String) && correlation.present?
        status = nil
        3.times do |attempt|
          sleep(0.3) if attempt.positive?
          command = @client.command_status(@organization_id, correlation)
          status = command["state"]
          if status == "Error" && command.dig("exception", "message") == "One or more objects used in edit session are already in use."
            return Pos::BillState.build(:syncing, reason: "Заказ сейчас редактируется в iikoFront. Закройте карточку заказа на кассе и обновите страницу.")
          end
          break unless status == "InProgress"
        end
        return Pos::BillState.build(:syncing) if status == "InProgress"
        return Pos::BillState.build(:unavailable, reason: "Не удалось синхронизировать заказ из iikoFront") unless status == "Success"
        response = @client.orders_by_table(@organization_id, table_id)
      end
      BillMapper.call(response, organization_id: @organization_id, table_id: table_id, currency: @currency)
    rescue Client::Error
      Pos::BillState.build(:unavailable, reason: "Кассовая система временно недоступна")
    end
  end
end
