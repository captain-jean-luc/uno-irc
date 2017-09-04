require "fast_irc"

module UnoIrc
  class Message
    property channel_name : String, nick : String, message_text : String, bot : FastIRCWrapper
    def initialize(@channel_name, @nick, @message_text, @bot)
    end

    def reply(msg_text : String)
      args = [] of String
      if !@channel_name.empty?
        args << @channel_name
      end
      args << msg_text
      fircmsg = FastIRC::Message.new("PRIVMSG", args)
      @bot.send fircmsg
    end
  end
end
