module Pos
  class QrBillService
    def self.load(token)
      return nil unless token.to_s.match?(/\A[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z/)
      table = OutletTable.active.includes(:merchant_outlet).find_by(qr_token: token)
      return nil unless table
      outlet = table.merchant_outlet
      result = { outlet: outlet, table: table, tips: outlet.outlet_tip_setting }
      result[:bill] = if outlet.pos_system == "r_keeper"
        BillState.build(:unavailable, reason: "Интеграция r_keeper пока недоступна")
      elsif outlet.pos_system == "iiko"
        load_iiko(outlet, table)
      else
        BillState.build(:unavailable, reason: "Для ресторана не настроена поддерживаемая POS-система")
      end
      result
    end

    def self.load_iiko(outlet, table)
      setting = outlet.outlet_iiko_setting
      connection = setting&.iiko_connection
      unless outlet.status != "disabled" && setting&.is_enabled && setting.merchant_id == outlet.merchant_id && connection&.verified? && connection.merchant_id == outlet.merchant_id
        return BillState.build(:unavailable, reason: "Кассовая система недоступна")
      end
      uuid = /\A[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z/
      ids = [setting.organization_id, setting.terminal_group_id, table.pos_table_id]
      unless ids.all? { |id| id.to_s.match?(uuid) && id.delete("-") != "0" * 32 }
        return BillState.build(:unavailable, reason: "Некорректная привязка стола iiko")
      end
      secret = Adapters::Iiko::KeyCipher.new.decrypt(connection.id, ciphertext: connection.api_key_ciphertext, nonce: connection.api_key_nonce, version: connection.encryption_key_version)
      client = Adapters::Iiko::Client.new(app_id: ENV.fetch("IIKO_APP_ID"), client_secret: ENV.fetch("IIKO_CLIENT_SECRET"), api_key: secret)
      adapter = Adapters::Iiko::Adapter.new(client: client, organization_id: setting.organization_id, terminal_group_id: setting.terminal_group_id)
      reader = Resolver.resolve(outlet.pos_system, [adapter])
      BillService.load(reader, merchant_id: outlet.merchant_id, outlet_id: outlet.id, table_id: table.pos_table_id, configured_pos: outlet.pos_system)
    rescue Adapters::Iiko::Client::Error, KeyError, ArgumentError, OpenSSL::Cipher::CipherError
      BillState.build(:unavailable, reason: "Не удалось получить счёт из кассовой системы")
    end
    private_class_method :load_iiko
  end
end
