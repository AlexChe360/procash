module Pos
  class Resolver
    class Error < StandardError; end
    def self.kind(value)
      { "iiko" => :iiko, "r_keeper" => :r_keeper, "rkeeper" => :r_keeper }[value]
    end
    def self.resolve(configured_pos, readers)
      kind = kind(configured_pos)
      raise Error, "POS не настроена или не поддерживается" unless kind
      matches = readers.select { |reader| reader.kind == kind }
      raise Error, "POS-адаптер недоступен или неоднозначен" unless matches.one?
      matches.first
    end
  end
end
