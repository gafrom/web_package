module WebPackage
  # This class is a convenience to represent an original response, later to be signed and packed.
  class InnerResponse
    include Helpers

    attr_reader :status, :headers, :body, :payload

    def initialize(status, headers, body)
      @status  = status
      @headers = prepare_headers(headers)
      @body    = body
      @payload = unrack_body
    end

    private

    def prepare_headers(headers)
      # The CBOR representation of a set of response metadata and headers is
      # the CBOR ([RFC7049]) map with the following mappings:
      #   - The byte string ':status' to the byte string containing the
      #     response's 3-digit status code, and
      #   - For each response header field, the header field's lowercase name
      #     as a byte string to the header field's value as a byte string.
      headers.dup.tap do |hsh|
        # only lowercase keys allowed
        hsh.keys.each { |key| hsh[key.to_s.downcase] = hsh.delete(key) }

        # TODO: find out why we need (or do not need) Link header for the purpose of
        #       serving Signed Http Exchange
        hsh.merge! ':status'                => bin(@status),
                   'content-encoding'       => 'mi-sha256-03',
                   'x-content-type-options' => 'nosniff'

        # inner cache directive is deleted because
        # exchange's response must be cacheable by a shared cache
        hsh.delete 'cache-control'
      end
    end

    def unrack_body
      @body.reduce('', :<<)
    end
  end
end
