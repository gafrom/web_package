module WebPackage
  # This class is a convenience to represent an original response, later to be signed and packed.
  class InnerResponse
    attr_reader :status, :headers, :body, :payload

    def initialize(status, headers, body)
      @status  = status
      @headers = headers
      @body    = body
      @payload = unrack_body
    end

    private

    def unrack_body
      payload = nil

      # Rack's body yields strings
      @body.each { |str| payload ? (payload << str) : (payload = str) }

      payload
    end
  end
end
