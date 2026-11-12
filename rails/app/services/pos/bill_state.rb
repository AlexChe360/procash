module Pos
  BillState = Data.define(:state, :order, :reason) do
    def self.build(state, order: nil, reason: nil) = new(state: state, order: order, reason: reason)
  end
end
