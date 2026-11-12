module PaymentProviders
  # Provider identifiers remain separate from bank-specific API adapters.
    # Listing a provider here does not mean the outlet is connected to it.
  module Registry
    PROVIDERS = { "freedom_pay" => { name: "Freedom Pay" }.freeze }.freeze
    DEFAULT = "freedom_pay".freeze

    def self.fetch(identifier) = PROVIDERS.fetch(identifier)
    def self.default = fetch(DEFAULT)
  end
end
