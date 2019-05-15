# encoding: ASCII-8BIT

module WebPackage
  # Builds headers and body of SXG format for a given pair of HTTP request-response.
  # SXG format allows a browser to trust that a single HTTP request/response pair was
  # generated by the origin it claims.
  #
  # Current implementation is lazy, meaning that signing is performed upon the
  # invocation of the `body` method.
  class SignedHttpExchange
    include Helpers

    SIGNATURE_MAX_SIZE = 2**14
    HEADERS_MAX_SIZE   = 2**19
    CERT_URL  = ENV.fetch 'SXG_CERT_URL'
    CERT_PATH = ENV.fetch 'SXG_CERT_PATH'
    PRIV_PATH = ENV.fetch 'SXG_PRIV_PATH'

    # Mock request-response pair just in case:
    MOCK_URL  = 'https://example.com/wow-fake-path'.freeze
    MOCK_RESP = [200, { 'Content-Type' => 'text/html; charset=utf-8' }, ['<h1>Hello!</h1>']].freeze

    # Accepts two args representing a request-response pair:
    #   url      - request url (string)
    #   response - an array, equivalent to Rack's one: [status_code, headers, body]
    def initialize(url = MOCK_URL, response = MOCK_RESP)
      @uri    = build_uri_from url
      @url    = @uri.to_s
      @inner  = InnerResponse.new(*response)
      @signer = Signer.new CERT_PATH, PRIV_PATH

      @digest, @payload_body = MICE.new.encode @inner.payload
      @inner.headers.merge! 'digest' => "mi-sha256-03=#{base64(@digest)}"
    end

    def headers
      Settings.headers
    end

    # https://tools.ietf.org/html/draft-yasskin-http-origin-signed-responses-05#section-5.3
    def body
      return @body if @body
      buffer = ''

      # 1. 8 bytes consisting of the ASCII characters "sxg1" followed by 4
      #    0x00 bytes, to serve as a file signature.  This is redundant with
      #    the MIME type, and recipients that receive both MUST check that
      #    they match and stop parsing if they don't.
      # TODO: The implementation of the final RFC MUST use the following line:
      # buffer << "sxg1\x00\x00\x00\x00"
      buffer << "sxg1-b3\x00"

      # 2.  2 bytes storing a big-endian integer "fallbackUrlLength".
      buffer << [@url.bytesize].pack('S>')

      # 3.  "fallbackUrlLength" bytes holding a "fallbackUrl", which MUST be
      #     an absolute URL with a scheme of "https".
      buffer << @url

      # 4.  3 bytes storing a big-endian integer "sigLength".  If this is
      #     larger than 16384 (16*1024), parsing MUST fail.
      if signature.bytesize > SIGNATURE_MAX_SIZE
        raise Errors::BodyEncodingError, 'Structured Signature Header length is too large: '\
              "#{signature.bytesize} bytes, max: #{SIGNATURE_MAX_SIZE} bytes."
      end
      buffer << [signature.bytesize].pack('L>').byteslice(-3, 3)

      # 5.  3 bytes storing a big-endian integer "headerLength".  If this is
      #     larger than 524288 (512*1024), parsing MUST fail.
      if cbor_encoded_headers.bytesize > HEADERS_MAX_SIZE
        raise Errors::BodyEncodingError, 'Response Headers length is too large: '\
              "#{cbor_encoded_headers.bytesize} bytes, max: #{HEADERS_MAX_SIZE} bytes."
      end
      buffer << [cbor_encoded_headers.bytesize].pack('L>').byteslice(-3, 3)

      # 6.  "sigLength" bytes holding the "Signature" header field's value
      #     (Section 3.1).
      buffer << signature

      # 7.  "headerLength" bytes holding "signedHeaders", the canonical
      #     serialization (Section 3.4) of the CBOR representation of the
      #     response headers of the exchange represented by the "application/
      #     signed-exchange" resource (Section 3.2), excluding the
      #     "Signature" header field.
      buffer << cbor_encoded_headers

      # 8.  The payload body (Section 3.3 of [RFC7230]) of the exchange
      #     represented by the "application/signed-exchange" resource.
      #     Note that the use of the payload body here means that a
      #     "Transfer-Encoding" header field inside the "application/signed-
      #     exchange" header block has no effect.  A "Transfer-Encoding"
      #     header field on the outer HTTP response that transfers this
      #     resource still has its normal effect.
      buffer << @payload_body

      @body = buffer
    end

    def to_rack_response
      [200, headers, [body]]
    end

    private

    def message
      return @message if @message
      buffer = ''

      # Help in debugging "VerifyFinal failed." error, source code:
      #   https://github.com/chromium/chromium/blob/8f0bd6c8be04f0dd556d42820f1eec0963dfe10b/
      #   content/browser/web_package/signed_exchange_signature_verifier.cc#L120
      # It may look as if something is wrong with the certificate or signing algorithm, but in fact
      # the error is caused by the message being composed incorrectly.
      # So, if you get such an error - please check the `message` first.

      # From specs:
      # https://tools.ietf.org/html/draft-yasskin-http-origin-signed-responses-05#section-3.5
      #
      # Let "message" be the concatenation of the following byte
      # strings.  This matches the [RFC8446] format to avoid cross-
      # protocol attacks if anyone uses the same key in a TLS
      # certificate and an exchange-signing certificate.

      # 1.  A string that consists of octet 32 (0x20) repeated 64 times.
      buffer << "\x20" * 64

      # 2.  A context string: the ASCII encoding of "HTTP Exchange 1".
      #     ... but implementations of drafts MUST NOT use it and MUST use another
      #     draft-specific string beginning with "HTTP Exchange 1 " instead.
      # TODO: The implementation of the final RFC MUST use the following line:
      # buffer << "HTTP Exchange 1"
      buffer << 'HTTP Exchange 1 b3'

      # 3.  A single 0 byte which serves as a separator.
      buffer << "\x00"

      # 4.  If "cert-sha256" is set, a byte holding the value 32
      #     followed by the 32 bytes of the value of "cert-sha256".
      #     Otherwise a 0 byte.
      buffer << (@signer.cert_sha256 ? "\x20#{@signer.cert_sha256}" : "\x00")

      # 5.  The 8-byte big-endian encoding of the length in bytes of
      #     "validity-url", followed by the bytes of "validity-url".
      buffer << [validity_url.bytesize].pack('Q>')
      buffer << validity_url

      # 6.  The 8-byte big-endian encoding of "date".
      buffer << [@signer.signed_at.to_i].pack('Q>')

      # 7.  The 8-byte big-endian encoding of "expires".
      buffer << [@signer.expires_at.to_i].pack('Q>')

      # 8.  The 8-byte big-endian encoding of the length in bytes of
      #     "requestUrl", followed by the bytes of "requestUrl".
      buffer << [@url.bytesize].pack('Q>')
      buffer << @url

      # 9.  The 8-byte big-endian encoding of the length in bytes of
      #     "responseHeaders", followed by the bytes of
      #     "responseHeaders".
      buffer << [cbor_encoded_headers.bytesize].pack('Q>')
      buffer << cbor_encoded_headers

      @message = buffer
    end

    def cbor_encoded_headers
      @cbor_encoded_headers ||= CBOR.new.generate @inner.headers
    end

    # returns a string representing serialized label + params
    def structured_header_for(label, params)
      if params[:'cert-url'].to_s.empty?
        raise '[SignedHttpExchange] No certificate url provided - please use `SXG_CERT_URL` '\
              'env var. Endpoint should respond with `application/cert-chain+cbor` content type.'
      end

      res = [label]

      params.sort.each do |key, value|
        # https://tools.ietf.org/html/draft-ietf-httpbis-header-structure-09#section-4.1.10
        res << "#{key}=" + case value
                           when Integer then value.to_s
                           when String  then %("#{value}")                   # a text string
                           when Array   then "*#{base64(value.pack('C*'))}*" # a byte string
                           end
      end

      res.join(?;)
    end

    # https://tools.ietf.org/html/draft-ietf-httpbis-header-structure-09
    def signature
      # Example of a signature:
      #   label;cert-sha256=*+DoXYlCX+bFRyW65R3bFA2ICIz8Tyu54MLFUFo5tziA=*;cert-url="https://exampl
      #   e.com/cert.cbor";date=1555925114;expires=1555928714;integrity="digest/mi-sha256-03";sig=*
      #   MEQCIBgsnVxmRqzjeFczuXnQClf2bwtHdGeGGSMOz6y5EH7HAiAu1lt2ERsWIRcOmszB3XneSWoGKrMD7wvalVfPp
      #   4tb9Q==*;validity-url="https://example.com/resource.validity.msg"
      @signature ||=
        structured_header_for 'label', 'cert-sha256':  @signer.cert_sha256.bytes,
                                       'cert-url':     Settings.cert_url,
                                       'date':         @signer.signed_at.to_i,
                                       'expires':      @signer.expires_at.to_i,
                                       'integrity':    'digest/mi-sha256-03',
                                       'sig':          @signer.sign(message).bytes,
                                       'validity-url': validity_url
    end

    def build_uri_from(url)
      u = url.is_a?(URI) ? url : URI(url)
      raise '[SignedHttpExchange] Request host is required' if u.host.nil?

      u
    end

    def validity_url
      @validity_url ||= begin
        path = @uri.path
        fi = path.index(?.)
        no_format_path = fi ? path[0...fi] : path # path without format, i.e. default :html

        URI::HTTPS.build(host: @uri.host, path: no_format_path, query: @uri.query).to_s
      end
    end
  end
end
