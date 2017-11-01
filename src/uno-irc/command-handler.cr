module UnoIrc
  class CommandHandler(T)

    # Arguments for a command callback:
    #   Command arguments : Array(String)
    #   Passthrough : T
    # Returns
    #   Response : String?
    #     Nil means no response.
    alias Callback = Proc(Array(String), T, Nil)
    alias WrapperCallback = Proc(String, Array(String), T, Callback, Nil)

    @wrappers : Hash(Symbol, WrapperCallback)
    @procs : Hash(String, NamedTuple(cb: Callback, wrappers: Array(Symbol)))
    @default_wrappers : Array(Symbol)
    @on_invalid : Proc(String, T, Nil)?

    def initialize
      @wrappers = Hash(Symbol, WrapperCallback).new
      @procs = {} of String => {cb: Callback, wrappers: Array(Symbol)}
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
      raise ArgumentError.new("Wrapper #{name.inspect} not defined") unless @wrappers.has_key? name
      @default_wrappers << name
      yield
      popped = @default_wrappers.pop
      if popped != name
        raise "This shouldn't happen"
      end
    end

    def on(command : String, *additional_wrappers : Array(Symbol), &callback : Callback) : Nil
      if @procs.has_key? command
        raise ArgumentError.new("#{command.inspect} already defined")
      end
      
      @procs[command] = {
        cb: callback,
        # This also effectively duplicates @default_wrappers when additional_wrappers is empty,
        # which is important.
        wrappers: @default_wrappers + additional_wrappers
      }
    end

    def on_invalid(&callback : Proc(String, T, Nil))
      raise ArgumentError.new("Cannot define on_invalid inside with_wrapper") unless @default_wrappers.empty?
      @on_invalid = callback
    end
    
    def handle_command(cmd : String, passthru : T) : Nil
      args = CommandParser.parse(cmd)
      command = args.first
      args = args[1..-1]
      info = @procs[command]?
      if info.nil?
        if (p = @on_invalid)
          p.call(cmd, passthru)
          return
        else
          raise "Invalid command, no handler specified"
        end
      end
      handle_wrappers(info[:wrappers], args, passthru) do
        info[:cb].call(args, passthru)
      end
    end

    private def handle_wrappers(wrappers : Array(Symbol), args : Array(String), passthru : T) : Nil
      if wrappers.empty?
        yield
      end
      this_wrapper = wrappers.pop
      cb = ->(new_args : Array(String), new_passthru : T){
        handle_wrappers(wrappers, new_args, new_passthru) do
          yield
        end
      }
      @wrappers[this_wrapper].call(args, passthru, cb)
    end
  end
end
