require 'openssl'
require 'singleton'

module WebPackage
  # Performs signing of a message with ECDSA.
  class Signer
    include Singleton
    include Helpers

    attr_reader :cert, :cert_url

    def self.take
      @@instance ||= new(Settings.cert_path, Settings.priv_path)
    end

    def initialize(path_to_cert, path_to_key)
      @alg  = OpenSSL::PKey::EC.new(File.read(path_to_key))
      @cert = OpenSSL::X509::Certificate.new(File.read(path_to_cert))
    end

    def sign(message)
      @alg.dsa_sign_asn1 digest(message)
    end

    def cert_sha256
      @cert_sha256 ||= digest(@cert.to_der)
    end
  end
end
