class AcquiringRequest < ApplicationRecord
  belongs_to :merchant
  belongs_to :merchant_outlet, foreign_key: :outlet_id
  belongs_to :requester, class_name: "User", foreign_key: :requested_by
  belongs_to :reviewer, class_name: "User", foreign_key: :reviewed_by, optional: true
  belongs_to :acquiring_connection, optional: true
  validates :provider, inclusion: { in: ->(_) { PaymentProviders::Registry::PROVIDERS.keys } }
  validates :status, inclusion: { in: %w[pending in_review approved rejected] }
  validates :review_note, length: { maximum: 1000 }
  validate :matching_context
  def provider_name = PaymentProviders::Registry.fetch(provider).fetch(:name)
  def status_label = { "pending" => "Заявка отправлена", "in_review" => "На рассмотрении", "approved" => "Одобрено ProCash", "rejected" => "Отклонено" }.fetch(status)
  private
  def matching_context
    errors.add(:outlet_id, "не принадлежит компании") unless merchant_outlet&.merchant_id == merchant_id
    connection = acquiring_connection
    if connection && [connection.merchant_id, connection.outlet_id, connection.provider] != [merchant_id, outlet_id, provider]
      errors.add(:acquiring_connection, "не соответствует заявке")
    end
  end
end
