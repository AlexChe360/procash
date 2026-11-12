require "ffi"

module Auth
  # libargon2 implements the same PHC format as Rust's Argon2::default().
  module Password
    module Native
      extend FFI::Library
      ffi_lib [ENV.fetch("ARGON2_LIBRARY", "argon2"), "/opt/homebrew/opt/argon2/lib/libargon2.dylib", "libargon2.so.1"]
      attach_function :argon2id_verify, [:string, :pointer, :size_t], :int
      attach_function :argon2id_hash_encoded, [:uint32, :uint32, :uint32, :pointer, :size_t, :pointer, :size_t, :size_t, :pointer, :size_t], :int
    end

    def self.hash(password)
      raise ArgumentError, "Пароль должен содержать 12–128 байт" unless (12..128).cover?(password.bytesize)
      salt = SecureRandom.random_bytes(16)
      output = FFI::MemoryPointer.new(:char, 256)
      result = Native.argon2id_hash_encoded(2, 19_456, 1, password, password.bytesize, salt, salt.bytesize, 32, output, 256)
      raise "Password hashing failed" unless result.zero?
      output.read_string
    end

    def self.verify(password, encoded)
      return false unless password.is_a?(String) && (1..128).cover?(password.bytesize)
      return false unless encoded.is_a?(String) && encoded.start_with?("$argon2id$") && !encoded.include?("\0")
      Native.argon2id_verify(encoded, password, password.bytesize).zero?
    end
  end
end
