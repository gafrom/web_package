module WebPackage
  # Merkle Integrity Content Encoding
  # https://tools.ietf.org/id/draft-thomson-http-mice-03.html
  class MICE
    include Helpers

    CHUNK_SIZE = 2**14 # bytes

    attr_reader :headers, :body

    def initialize(headers, body)
      @body    = body.dup
      @headers = headers.dup.tap do |hsh|
        # only lowercase keys allowed
        hsh.keys.each { |key| hsh[key.to_s.downcase] = hsh.delete(key) }
      end

      @encoded = false
    end

    def encode!
      return if encoded?

      @root_digest, @body = interlace_body_with_digests
      @headers.merge! 'content-encoding'       => 'mi-sha256-03',
                      'digest'                 => "mi-sha256-03=#{base64(@root_digest)}",
                      'x-content-type-options' => 'nosniff'
      # TODO: find out why we need (or do not need) Link header for the purpose of
      #       serving Signed Http Exchange
      #       linkHeader, err := formatLinkHeader(metadata.Preloads)
      #       fetchResp.Header.Set("Link", linkHeader)

      @encoded = true
    end

    def encoded?
      @encoded
    end

    private

    def interlace_body_with_digests
      num_parts = @body.bytesize.fdiv(CHUNK_SIZE).ceil

      chunks = []
      proofs = []

      num_parts.times do |i|
        delimeter = i.zero? && "\x00" || "\x01"
        ri = num_parts - i - 1

        chunks << force_bin(@body.byteslice(ri * CHUNK_SIZE, CHUNK_SIZE))
        proofs << digest("#{chunks.last}#{proofs.last}#{delimeter}")
      end

      chunks << [CHUNK_SIZE].pack('Q>')

      return proofs.pop, chunks.zip(proofs).flatten.reverse!.join
    end
  end
end
