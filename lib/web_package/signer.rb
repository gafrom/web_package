require 'openssl'

module WebPackage
  # Performs signing of a message with ECDSA.
  class Signer
    include Helpers
    attr_reader :signed_at, :expires_at, :cert, :integrity, :cert_url

    def initialize(path_to_cert, path_to_key)
      @alg  = OpenSSL::PKey::EC.new(File.read(path_to_key))
      @cert = OpenSSL::X509::Certificate.new(File.read(path_to_cert))

      @signed_at  = Time.zone.now
      @expires_at = @signed_at + 7.days
    end

    def sign(message)
      @alg.dsa_sign_asn1 digest(message)
    end

    def cert_sha256
      @cert_sha256 ||= digest(@cert.to_der)
    end
  end
end
