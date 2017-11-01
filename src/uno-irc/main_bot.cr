module UnoIrc
  class MainBot

    @chan : String?
    @user : String?

    def initialize(
          @command_prefix : String,
          @channels_to_join : Array(String),
          @my_nick : String = "BetterUNOBot",
          @server_name : String,
          @server_port : UInt16 = 6667,
          @server_ssl : Bool = false)
      @games = {} of String => Game
      @command_handler = CommandHandler.new

      @irc = FastIRCWrapper.new(
        nick: @my_nick,
        server: @server_name,
        port: @server_port,
      )

      @irc.on_message do |msg|
        msg.to_s(STDOUT)
      end

      # Kill switch, just in case
      @irc.on("PRIVMSG") do |msg|
        if msg.params.last.starts_with? "DIEUNODIE"
          begin
            STDERR.puts "Received killswitch, #{msg.inspect}"
          ensure
            exit 1
          end
        end
      end

      @irc.on("PRIVMSG") do |fast_irc_msg|
        if !@user.nil?
          STDERR.puts "@user was supposed to be nil, it wasn't"
          @user = nil
        end
        @chan = nil
        case fast_irc_msg.params.size
        when 1
          is_channel_msg = false
        when 2
          is_channel_msg = true
          @chan = fast_irc_msg.params.first
        else
          ssl: @server_ssl
          STDERR.puts "This is a weird server"
          next
        end
        message_text = fast_irc_msg.params.last
        @user = fast_irc_msg.prefix.source
        if message_text.starts_with? @command_prefix
          command_text = message_text[@command_prefix.size..-1]
          @command_handler.handle_command(command_text)
        end
      end

      @irc.on("PART") do |msg|
        self.remove_player?(msg)
      end
      @irc.on("QUIT") do |msg|
        self.remove_player?(msg)
      end
      @irc.on("NICK") do |msg|
        self.nick_change(msg)
      end

      @irc.on("001") do
        @channels_to_join.each do |channel_name|
          @irc.send FastIRC::Message.new("JOIN", channel_name)
        end
      end

      @irc.on("PING") do |msg|
        @irc.send( FastIRC::Message.new("PONG", msg.params) )
      end

      ch = @command_handler

      ch.on_invalid do |cmd|
        reply "Unrecognized command #{@command_prefix}#{cmd.name}"
      end
      ch.make_wrapper :in_channel do |cmd, cb|
        if @chan.nil?
          reply "This command can only be used in a channel"
        else
          cb.call(cmd)
        end
      end

      ch.make_wrapper :in_game do |cmd, cb|
        if @games.has_key? chan
          cb.call(cmd)
        else
          reply "This command can only be used during a game. Try '#{@command_prefix}uno' to create a game"
        end
      end

      ch.make_wrapper :is_current_player do |cmd, cb|
        per = game.find_player(user)
        if per.nil?
          reply "@#{user}, you're not in the game. Sorry."
        elsif per != game.current_player
          reply "@#{user}, it's not your turn. Just hold on a sec, okay?"
        end
      end

      ch.make_wrapper :is_game_master do |cmd, cb|
        if user == game.players.first.name
          cb.call(cmd)
        else
          reply "Only the Game Master #{game.players.first.name} may use this command. You do not have the power!"
        end
      end

      #TODO: sudo
      ch.on "info", "help", "h", "?" do
        reply "I am the Better UNO Bot version #{UnoIrc::VERSION}, by jean-luc. Type '#{@command_prefix}uno' to start a new game. Source available at: https://github.com/captain-jean-luc/uno-irc"
      end

      ch.with_wrapper :in_channel do
        ch.on "uno", "startuno", "unostart", "start" do
          if @games.has_key? chan
            reply "Game already started by #{current_game!.players.first.name}! Type #{@command_prefix}"
          else
            g = @games[chan] = Game.new
            g.on_update do |upd|
              self.handle_game_update(upd)
            end
            g.add_player(user)
            reply "Game started! Type '#{@command_prefix}join' to join!"
          end

          ch.with_wrapper :in_game do
            ch.on "ujoin", "unojoin", "join", "j", "joinuno", "uj" do
              if game.players.any?{|per| per.name == user}
                reply "@#{user}, you've already joined!"
              else
                game.add_player(n)
                reply "#{user} has joined UNO! Game Master may type '#{@command_prefix}deal' to start the game"
              end
            end
            ch.on "deal", wrap: :is_game_master do
              game.deal
            end
            #ch.on "end", "stop", "enduno", "stopuno", "unoend", "unostop" do
              #TODOLATER
            #end
            ch.with_wrapper :is_current_player do
              ch.on "play", "p", /^p[^a]/ do |cmd|
                self.play_card(cmd) #TODO: Implement
              end
              ch.on "d", "draw" do
                game.voluntary_draw
              end
              ch.on "drawpass", "dp" do
                game.drawpass
              end
              ch.on "pass", "pa" do
                game.pass
              end
            end
          end
        end


      end
    end

    def chan
      @chan.not_nil!
    end

    def user
      @user.not_nil!
    end

    def game
      @games[chan]
    end

    def reply_target
      @chan || @user.not_nil!
    end

    def reply(msg : String)
      @irc.send( FastIRC::Message.new("NOTICE", [reply_target, msg]) )
    end
