require "openssl"
require "base64"

module PaymentProviders
  class SecretCipher
    def initialize(key: Base64.strict_decode64(ENV.fetch("PROCASH_ENCRYPTION_KEY_V1").strip))
      raise ArgumentError, "Invalid encryption key" unless key.bytesize == 32
      @key = key
    end

    def encrypt(id, secret)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = @key
      nonce = SecureRandom.random_bytes(12)
      cipher.iv = nonce
      cipher.auth_data = aad(id)
      { secret_ciphertext: cipher.update(secret) + cipher.final + cipher.auth_tag,
        secret_nonce: nonce, encryption_key_version: 1 }
    end

    def decrypt(connection)
      raise ArgumentError, "Unsupported encrypted credentials" unless connection.encryption_key_version == 1
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = @key
      cipher.iv = connection.secret_nonce
      cipher.auth_tag = connection.secret_ciphertext.byteslice(-16, 16)
      cipher.auth_data = aad(connection.id)
      (cipher.update(connection.secret_ciphertext.byteslice(0...-16)) + cipher.final).force_encoding("UTF-8")
    end

    def inspect = "#<#{self.class.name} [FILTERED]>"
    private
    def aad(id) = "procash:acquiring:connection:v1:#{id}"
  end
end
