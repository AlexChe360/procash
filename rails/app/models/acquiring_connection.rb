class AcquiringConnection < ApplicationRecord
  belongs_to :merchant
  belongs_to :merchant_outlet, foreign_key: :outlet_id
  has_many :acquiring_requests
  self.filter_attributes += [:secret_ciphertext, :secret_nonce]

  validates :name, length: { in: 2..100 }
  validates :provider, inclusion: { in: ->(_) { PaymentProviders::Registry::PROVIDERS.keys } }
  validates :environment, inclusion: { in: %w[test live] }
  validates :provider_merchant_id, format: { with: /\A[0-9]{1,64}\z/, message: "Merchant ID должен содержать цифры" }
  validates :provider_merchant_id, uniqueness: { scope: [:outlet_id, :provider, :environment], message: "уже добавлен для этого провайдера и режима" }
  validate :same_company
  scope :available, -> { where(disabled_at: nil) }

  def secret_saved? = secret_ciphertext.present?
  def disabled? = disabled_at.present?
  def provider_name = PaymentProviders::Registry.fetch(provider).fetch(:name)
  def environment_label = environment == "live" ? "Боевой" : "Тестовый"
  def status_label = disabled? ? "Отключено" : secret_saved? ? "Реквизиты сохранены" : "Нужен секретный ключ"

  private
  def same_company
    errors.add(:outlet_id, "не принадлежит компании") if merchant_outlet && merchant_outlet.merchant_id != merchant_id
  end
end
