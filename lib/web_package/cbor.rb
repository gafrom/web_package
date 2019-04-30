module WebPackage
  # Concise Binary Object Representation
  # https://tools.ietf.org/html/rfc7049
  class CBOR
    include Helpers

    # Major type 0: an unsigned integer.
    # Major type 1: a negative integer.
    # Major type 2: a byte string.
    # Major type 3: a text string, Unicode characters that is encoded as UTF-8 [RFC3629].
    # Major type 4: an array of data items.
    # Major type 5: a map of pairs of data items.
    # Major type 6: optional semantic tagging of other major types.
    # Major type 7: floating-point numbers and simple data types that need no content.
    MAJOR_TYPES_RANGE = 0..7

    def generate(input)
      generate_bytes(input).pack('C*')
    end

    private

    # https://tools.ietf.org/html/rfc7049#section-2.1
    def generate_bytes(input)
      case input
      when Hash
        input = input.transform_keys { |key| bin(key) }

        bytes = hsh_size(input)
        bytes[0] |= major_type(5)

        input.keys.sort_by(&:bytesize).each do |key|
          bytes.concat generate_bytes(key)
          bytes.concat generate_bytes(input[key])
        end
      when String, Symbol
        input = input.to_s
        bytes = str_size(input)
        # rubocop: disable Style/IdenticalConditionalBranches
        # TODO: Use major_type(3) for non-binary strings.
        #       Right now all strings are encoded as byte strings because Chrome eats only such.
        #       So, we need to either proove wrong, or submit an issue to chromium dev.
        bytes[0] |= input.encoding == Encoding::BINARY ? major_type(2) : major_type(2)
        # rubocop: enable Style/IdenticalConditionalBranches
        bytes.concat input.bytes
      when Integer
        raise '[CBOR] Not implemented for negative integers' if input.negative?

        bytes = int_size(input)
        bytes[0] |= major_type(0) # a positive integer
      else
        raise "[CBOR] Not implemented for #{input.class} class"
      end

      bytes
    end

    def major_type(num)
      unless MAJOR_TYPES_RANGE.include? num
        raise "[CBOR] Cannot infer Major Type from int #{num}, which is outside of allowed range."
      end

      # the type takes up 3 most significant bits of first byte
      num << 5
    end

    def hsh_size(hsh)
      size = hsh.size
      raise '[CBOR] Not implemented for the hash of size more than 23 pairs' unless size < 24

      [size]
    end

    def str_size(s)
      int_size s.bytesize
    end

    def int_size(num)
      case num
      when     0...   24 then [num]
      when    24... 2**8 then [24, *[num].pack('C').bytes]
      when  2**8...2**16 then [25, *[num].pack('S>').bytes]
      when 2**16...2**32 then [26, *[num].pack('L>').bytes]
      when 2**32...2**64 then [27, *[num].pack('Q>').bytes]
      else raise '[CBOR] Not implemented for integers greater than (2**64 - 1) bits'
      end
    end
  end
end
