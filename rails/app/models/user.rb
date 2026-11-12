class User < ApplicationRecord
  has_many :merchant_memberships
  has_many :merchants, through: :merchant_memberships
  has_many :user_sessions

  scope :eligible, -> { where(is_active: true).where.not(email_verified_at: nil) }

  def self.authenticate(email, password, role:)
    email = email.to_s.strip.downcase
    return nil unless (5..254).cover?(email.bytesize) && (1..128).cover?(password.to_s.bytesize)
    account = eligible.where(platform_role: role).find_by("LOWER(email) = ?", email)
    account = nil if role == "user" && account && !account.merchant_memberships.where(is_active: true).exists?
    # Run a hash verification even when the account is absent.
    encoded = account&.password_hash || dummy_hash
    valid = Auth::Password.verify(password, encoded)
    account if valid
  end

  def self.dummy_hash
    @dummy_hash ||= Auth::Password.hash("dummy-account-password-not-for-login")
  end

  def admin? = platform_role == "admin"
end
