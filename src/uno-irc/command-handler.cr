require "./command-parser"

module UnoIrc
  record Command, name : String, args : Array(String) do
    def initialize(a : Array(String))
      raise ArgumentError.new if a.empty?
      @name = a[0]
      @args = a[1..-1]
    end
  end

  class CommandHandler
    alias Callback = Proc(Command, Nil)
    alias WrapperCallback = Proc(Command, Callback, Nil)

    @on_invalid : Proc(Command, Nil)?

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
           wrap : (Enumerable(Symbol) | Symbol) = [] of Symbol,
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

    def on_invalid(&callback : Proc(Command, Nil))
      unless @default_wrappers.empty?
        raise ArgumentError.new("Cannot define on_invalid inside with_wrapper")
      end
      @on_invalid = callback
    end

    def handle_command(cmd : String) : Nil
      args = CommandParser.parse(cmd)
      #pp cmd, args
      command = Command.new(args)
      handle_command(command)
    end

    def handle_command(command : Command)
      puts "Attempting to handle command #{command}"
      handled = false
      @procs.each do |info|
        puts "checking #{info}"
        case (to_match = info[:match])
        when Regex
          next if to_match.match(command.name).nil?
        when String
          next if to_match != command.name
        else
          raise "This isn't supposed to happen"
        end
        puts "matched #{info}"
        handled = true
        handle_wrappers(info[:wrappers], command) do |new_cmd|
          puts "calling with #{new_cmd}"
          info.not_nil![:cb].call(new_cmd)
        end
      end
      if !handled && !(oninval = @on_invalid).nil?
        oninval.call(command)
      end
    end

    private def handle_wrappers(wrappers : Array(Symbol),
                                command : Command,
                                &block : Proc(Command, Nil)) : Nil
      if wrappers.empty?
        yield command
        return
      end
      this_wrapper = wrappers.last
      puts "handling #{this_wrapper} wrapper"
      cb = ->(new_cmd : Command){
        handle_wrappers(wrappers[0...-1], new_cmd) do |cmd|
          block.call(cmd)
        end
      }
      @wrappers[this_wrapper].call(command, cb)
    end
  end
end
