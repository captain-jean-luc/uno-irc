require "openssl"
require "fast_irc"

class NotConnectedError < Exception
end

# A wrapper for fast_irc

class FastIRCWrapper
  alias Callback = FastIRC::Message ->

  @socket : IO?
  @hooks = {} of String => Array(Callback)
  @global_hooks = [] of Callback

  @server : String
  @port : UInt16
  @nick : String
  @user : String
  @realname : String
  @ssl : Bool

  property nick

  def initialize(
        @server,
        @port,
        @nick,
        user = nil,
        @realname = "bob",
        @ssl = false
      )
    if user.nil?
      @user = @nick
    else
      @user = user
    end
  end

  def socket
    raise NotConnectedError.new() if (s = @socket).nil?
    return s
  end

  def connect
    sock = TCPSocket.new @server, @port
    sock = OpenSSL::SSL::Socket::Client.new(sock) if @ssl
    @socket = sock
    send_login
    spawn do
      FastIRC.parse(sock) do |message|
        process(message)
      end
    end
  end

  def privmsg(target : String, text : String)
    send(FastIRC::Message.new("PRIVMSG", [target, text]))
  end

  def notice(target : String, text : String)
    send(FastIRC::Message.new("NOTICE", [target, text]))
  end

  def on_message(&block : Callback)
    @global_hooks << block
  end

  def on(cmd : String, &block : Callback)
    cmd = cmd.upcase
    @hooks[cmd] ||= [] of Callback
    @hooks[cmd] << block
  end

  def send(msg : FastIRC::Message | String | Bytes)
    msg.to_s(socket)
  end

  def send_line(data)
    s = socket
    s.print data
    s.write_byte 0x0D_u8 # \r carridge return
    s.write_byte 0x0A_u8 # \n new line
  end

  def send_login
    #n = @nick.to_s
    #u = @user.to_s
    #r = @realname.to_s
    #pp n, u, r
    send_line "NICK #{@nick}"
    send_line "USER #{@user} 0 * :#{@realname}"
  end

  private def process(msg)
    @global_hooks.each do |hook|
      spawn { hook.call(msg) }
    end

    if (hooks = @hooks[msg.command.upcase]?)
      hooks.each do |hook|
        spawn { hook.call(msg) }
      end
    end
  end
end
