require 'digest/sha2'
require 'base64'

module WebPackage
  # Helper methods used in the library.
  module Helpers
    private

    def bin(s)
      force_bin(s.is_a?(String) ? s.dup : s.to_s)
    end

    def force_bin(s)
      s.force_encoding Encoding::ASCII_8BIT
    end

    def digest(s)
      Digest::SHA256.digest s
    end

    def base64(s)
      Base64.strict_encode64 s
    end
  end
end
