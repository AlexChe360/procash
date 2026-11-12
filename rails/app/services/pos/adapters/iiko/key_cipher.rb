require "openssl"
require "base64"

module Pos::Adapters::Iiko
  class KeyCipher
    def initialize(key: Base64.strict_decode64(ENV.fetch("PROCASH_ENCRYPTION_KEY_V1").strip))
      raise ArgumentError, "Invalid master key" unless key.bytesize == 32
      @key = key
    end

    def encrypt(connection_id, secret)
      raise ArgumentError, "Empty API key" if secret.strip.empty?
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = @key
      nonce = SecureRandom.random_bytes(12)
      cipher.iv = nonce
      cipher.auth_data = aad(connection_id)
      ciphertext = cipher.update(secret) + cipher.final + cipher.auth_tag
      { api_key_ciphertext: ciphertext, api_key_nonce: nonce, encryption_key_version: 1 }
    end

    def decrypt(connection_id, ciphertext:, nonce:, version:)
      raise ArgumentError, "Unsupported key version" unless version == 1
      raise ArgumentError, "Invalid encrypted key" unless nonce.bytesize == 12 && ciphertext.bytesize > 16
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = @key
      cipher.iv = nonce
      cipher.auth_tag = ciphertext.byteslice(-16, 16)
      cipher.auth_data = aad(connection_id)
      plaintext = (cipher.update(ciphertext.byteslice(0, ciphertext.bytesize - 16)) + cipher.final).force_encoding("UTF-8")
      raise ArgumentError, "Invalid UTF-8" unless plaintext.valid_encoding?
      plaintext
    end

    def inspect = "#<#{self.class.name} [FILTERED]>"
    private
    def aad(id) = "procash:iiko:connection:v1:#{id}"
  end
end
