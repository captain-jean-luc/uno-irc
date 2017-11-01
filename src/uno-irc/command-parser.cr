module UnoIrc
  module CommandParser
    WHITESPACE_CHARS = {'\t', ' '}
    
    def self.parse(cmd : String) : Array(String)
      args = [] of String
      current_str = String::Builder.new
      parser_state = :start
      reader = IO::Memory.new(cmd)
      while (c = reader.read_char)
        case parser_state
        when :start
          current_str << c
          parser_state = :reading_arg
        when :reading_arg
          if WHITESPACE_CHARS.includes? c
            args << current_str.to_s
            current_str = String::Builder.new
            parser_state = :skipping_whitespace
          elsif c == '"'
            parser_state = :in_quote
          else
            current_str << c
          end
        when :in_quote
          if c == '"'
            parser_state = :reading_arg
          elsif c == '\\'
            parser_state = :escaped_char
          else
            current_str << c
          end
        when :escaped_char
          current_str << c
          parser_state = :in_quote
        when :skipping_whitespace
          if WHITESPACE_CHARS.includes? c
          # do nothing
          else
            parser_state = :reading_arg
            reader.seek(-1, IO::Seek::Current) #re-read this character
          end
        end
      end
      case parser_state
      when :reading_arg
        # valid
        args << current_str.to_s
      when :skipping_whitespace
      # valid, already to args
      # do nothing
      else
        # invalid
        # TODO: complain instead of just continuing
      end

      return args
    end
  end
end
