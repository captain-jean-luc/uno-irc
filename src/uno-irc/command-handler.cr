require "./command-parser"

module UnoIrc
  class CommandHandler#(T)

    # Arguments for a command callback:
    #   Command arguments : Array(String)
    #   Passthrough : T
    # Returns
    #   Response : String?
    #     Nil means no response.

    alias T = Hash(Symbol, String)

    #record Callback, value : Proc(Array(String), T, Nil) do
    #  delegate call, to: value
    #end
    alias Callback = Proc(Array(String), T, Nil)
    #macro callback
    #  (Proc(Array(String), T, Nil))
    #end

    #record WrapperCallback, value : Proc(String, Array(String), T, Proc(Array(String), T, Nil), Nil) do
    #  delegate call, to: value
    #end
    alias WrapperCallback = Proc(String, Array(String), T, Callback, Nil)
    #macro wrapperCallback
    #  (Proc(String, Array(String), T, Callback, Nil))
    #end

    #record WrapperCallbackWrapper, value : WrapperCallback

    @wrappers : Hash(Symbol, WrapperCallback)
    #@procs : Array(
    #    NamedTuple(match: (String | Regex), cb: Callback, wrappers: Array(Symbol))
    #  )
    @default_wrappers : Array(Symbol)
    @on_invalid : Proc(String, T, Nil)?

    def initialize
      @wrappers = Hash(Symbol, WrapperCallback).new
      @procs = [] of NamedTuple(
        match: (String | Regex),
        cb: Callback,
        wrappers: Array(Symbol)
      )
      @default_wrappers = [] of Symbol
      @on_invalid = nil
    end

    def make_wrapper(name : Symbol, &callback : WrapperCallback) : Nil
      if @wrappers.has_key? name
        raise ArgumentError.new("#{name.inspect} already defined")
      end
      @wrappers[name] = callback
    end

    def with_wrapper(name : Symbol) : Nil
      unless @wrappers.has_key? name
        raise ArgumentError.new("Wrapper #{name.inspect} not defined")
      end
      @default_wrappers << name
      yield
      popped = @default_wrappers.pop
      if popped != name
        raise "This shouldn't happen"
      end
    end

    def on(*commands : (String | Regex),
           wrap : Enumerable(Symbol) | Symbol = [] of Symbol,
           &callback : Callback) : Nil
      if wrap.is_a? Symbol
        wrap = [wrap]
      end
      commands.each do |command|
        @procs << {
          match: command,
          cb: callback,
          # This also effectively duplicates @default_wrappers when
          # additional_wrappers is empty, which is important.
          wrappers: @default_wrappers + wrap.to_a
        }
      end
    end

    def on_invalid(&callback : Proc(String, T, Nil))
      unless @default_wrappers.empty?
        raise ArgumentError.new("Cannot define on_invalid inside with_wrapper")
      end
      @on_invalid = callback
    end

    def handle_command(cmd : String, passthru : T) : Nil
      args = CommandParser.parse(cmd)
      pp cmd, args
      command = args.first
      args = args[1..-1]
      handle_command(command, args, passthru)
    end

    def handle_command(command : String, args : Array(String), passthru : T)
      handled = false
      @procs.each do |info|
        case (to_match = info[:match])
        when Regex
          next if !to_match.match(command)
        when String
          next if to_match != command
        else
          raise "This isn't supposed to happen"
        end
        handled = true
        handle_wrappers(info[:wrappers], command, args, passthru) do |na, np|
          info.not_nil![:cb].call(na, np)
        end
      end
      if !handled && !(oninval = @on_invalid).nil?
        oninval.call(cmd, passthru)
      end
    end

    private def handle_wrappers(wrappers : Array(Symbol),
                                command : String,
                                args : Array(String),
                                passthru : T,
                                &block : Proc(Array(String), T, Nil)) : Nil
      if wrappers.empty?
        yield args, passthru
        return
      end
      this_wrapper = wrappers.last
      cb = ->(new_args : Array(String), new_passthru : T){
        handle_wrappers(wrappers[0...-1], command, new_args, new_passthru) do |na, np|
          block.call(na, np)
        end
      }
      @wrappers[this_wrapper].call(command, args, passthru, cb)
    end
  end
end
