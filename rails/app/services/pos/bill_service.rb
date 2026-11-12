module Pos
  class BillService
    def self.load(reader, merchant_id:, outlet_id:, table_id:, configured_pos:)
      raise Resolver::Error, "POS-адаптер не соответствует настройкам" unless reader.kind == Resolver.kind(configured_pos)
      ids = [merchant_id, outlet_id]
      raise Resolver::Error, "Некорректный контекст" unless ids.all? { |id| id.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i) && id.delete("-") != "0" * 32 }
      raise Resolver::Error, "Не указан стол POS" if table_id.to_s.strip.empty?
      reader.load_bill(table_id)
    end
  end
end
