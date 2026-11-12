require "openssl"
require "digest"

class MerchantInvitation < ApplicationRecord
  belongs_to :merchant
  belongs_to :connection_request
  has_one :merchant_invitation_outbox

  def self.secret
    encoded = ENV.fetch("INVITATION_TOKEN_SECRET")
    raise ArgumentError, "Invitation secret must be 32 hex bytes" unless encoded.match?(/\A[0-9a-fA-F]{64}\z/)
    [encoded].pack("H*")
  end

  def self.token_for(id, key: secret)
    bytes = [id.delete("-")].pack("H*")
    signature = OpenSSL::HMAC.hexdigest("SHA256", key, "procash:merchant-invitation:v1:".b + bytes)
    "#{id}.#{signature}"
  end

  def self.valid_token_id(token)
    return nil unless token.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.[0-9a-f]{64}\z/)
    id = token.split(".").first
    id if ActiveSupport::SecurityUtils.secure_compare(token_for(id), token)
  end

  def self.for_token(token)
    id = valid_token_id(token)
    return nil unless id
    invitation = where(id: id, accepted_at: nil, revoked_at: nil, token_hash: Digest::SHA256.digest(token)).where("expires_at > ?", Time.current).first
    request = invitation&.connection_request
    invitation if request && request.status == "approved" && request.merchant_id == invitation.merchant_id
  end

  def self.issue!(request, admin)
    request.with_lock do
      raise ArgumentError, "Нужна одобренная заявка и компания" unless request.status == "approved" && request.merchant_id
      raise ArgumentError, "Владелец уже активирован" if request.merchant.merchant_memberships.where(role: "owner", is_active: true).exists?
      pending = where(merchant_id: request.merchant_id, accepted_at: nil, revoked_at: nil)
      pending.where("expires_at <= ?", Time.current).update_all(revoked_at: Time.current)
      if (existing = pending.first)
        message = existing.merchant_invitation_outbox&.sent_at ? "Приглашение уже отправлено. Повторное письмо не отправлено." : "Приглашение уже создано и ожидает отправки. Повторное письмо не добавлено."
        raise ArgumentError, message
      end
      id = SecureRandom.uuid
      invitation = create!(id: id, merchant: request.merchant, connection_request: request, email: request.contact_email.strip.downcase,
        token_hash: Digest::SHA256.digest(token_for(id)), created_by: admin.id, expires_at: 48.hours.from_now)
      invitation.create_merchant_invitation_outbox!
      invitation
    end
  end

  def self.activate!(token, password)
    hash = Auth::Password.hash(password)
    transaction do
      invitation = for_token(token)
      raise ArgumentError, "Приглашение недействительно" unless invitation
      invitation.lock!
      raise ArgumentError, "Приглашение недействительно" unless for_token(token)
      invitation.merchant.lock!
      raise ArgumentError, "Владелец уже существует" if invitation.merchant.merchant_memberships.where(role: "owner", is_active: true).exists?
      email = invitation.email.strip.downcase
      raise ArgumentError, "Аккаунт уже существует" if User.where("LOWER(email) = ?", email).exists?
      user = User.create!(email: email, password_hash: hash, display_name: invitation.connection_request.contact_name, platform_role: "user", email_verified_at: Time.current)
      MerchantMembership.create!(merchant: invitation.merchant, user: user, role: "owner")
      invitation.update!(accepted_at: Time.current)
      user
    end
  end
end
