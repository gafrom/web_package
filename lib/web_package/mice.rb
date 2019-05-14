module WebPackage
  # Merkle Integrity Content Encoding
  # https://tools.ietf.org/id/draft-thomson-http-mice-03.html
  class MICE
    include Helpers

    CHUNK_SIZE = 2**14 # bytes

    def encode(text)
      num_parts = text.bytesize.fdiv(CHUNK_SIZE).ceil

      chunks = []
      proofs = []

      num_parts.times do |i|
        delimeter = i.zero? && "\x00" || "\x01"
        ri = num_parts - i - 1

        chunks << force_bin(text.byteslice(ri * CHUNK_SIZE, CHUNK_SIZE))
        proofs << digest("#{chunks.last}#{proofs.last}#{delimeter}")
      end

      chunks << [CHUNK_SIZE].pack('Q>')

      return proofs.pop, chunks.zip(proofs).flatten.reverse!.join
    end
  end
end
