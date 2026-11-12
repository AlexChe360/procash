require "digest"

class UserSession < ApplicationRecord
  belongs_to :user
  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(user)
    token = SecureRandom.hex(32)
    create!(user: user, token_hash: Digest::SHA256.digest(token), expires_at: 12.hours.from_now)
    token
  end

  def self.for_token(token)
    return nil unless token.is_a?(String) && token.match?(/\A[0-9a-fA-F]{64}\z/)
    live.find_by(token_hash: Digest::SHA256.digest(token))
  end
end
