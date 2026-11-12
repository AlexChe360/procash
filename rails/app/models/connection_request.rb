class ConnectionRequest < ApplicationRecord
  belongs_to :merchant, optional: true
  has_one :email_outbox
  attr_accessor :consent
  validates :contact_name, :city, length: { in: 2..100 }
  validates :establishment_name, length: { in: 2..150 }
  validates :comment, length: { maximum: 1000 }
  validates :bin_iin, format: { with: /\A[0-9]{12}\z/, message: "БИН/ИИН должен содержать 12 цифр" }, allow_nil: true
  validates :pos_system, inclusion: { in: %w[iiko r_keeper poster other] }, allow_blank: true
  validates :consent, inclusion: { in: ["yes"] }, on: :create
  validate :valid_contact
  before_validation :normalize_contact
  before_create { self.consent_accepted_at = Time.current }
  after_create { create_email_outbox! }

  def transition!(target, reviewer)
    with_lock do
      allowed = status == "new" ? ["in_review"] : status == "in_review" ? %w[approved rejected] : []
      raise ArgumentError, "Недопустимый переход статуса" unless allowed.include?(target)
      update!(status: target, reviewed_by: reviewer.id, reviewed_at: Time.current)
    end
  end

  def create_merchant!(legal_name:, bin_iin:)
    with_lock do
      raise ArgumentError, "Заявка не одобрена или компания уже создана" unless status == "approved" && merchant_id.nil?
      update!(merchant: Merchant.create!(legal_name: legal_name.strip, bin_iin: bin_iin.strip, status: "draft"))
      merchant
    end
  end

  private

  def normalize_contact
    self.bin_iin = bin_iin&.strip.presence
    %w[contact_name contact_email contact_phone establishment_name city comment].each do |field|
      self[field] = self[field]&.strip
    end
    self.contact_email = contact_email&.downcase
  end

  def valid_contact
    local, domain = contact_email.to_s.split("@", 2)
    unless contact_email.to_s.bytesize <= 254 && local.present? && domain&.include?(".") && !domain.start_with?(".") && !domain.end_with?(".") && !contact_email.match?(/\s/)
      errors.add(:contact_email, "Укажите корректный email")
    end
    phone = contact_phone.to_s
    unless (10..15).cover?(phone.count("0-9")) && phone.bytesize <= 32 && phone.match?(/\A[0-9+ ()-]+\z/)
      errors.add(:contact_phone, "Укажите корректный телефон")
    end
  end
end
