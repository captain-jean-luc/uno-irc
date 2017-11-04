require "../fast_irc_wrapper.cr"
struct FastIRC::Message # Some monkey-patching
  def params
    res = previous_def
    if res.nil?
      return [] of String
    else
      return res
    end
  end
end

module UnoIrc
  class MainBot
    module Util
      extend self

      COLOR_NUMS = {
        Color::Red => 4,
        Color::Green => 3,
        Color::Blue => 12,
        Color::Yellow => 8,
        Color::Wild => 0
      }

      def hand_of(player : Player, game : Game)
        msg1 = "" #"Your hand: "
        msg2 = "" #"Playable cards: "
        sorted = player.hand.sort_by do |c|
          {c.color_for_equality_test, c.class.to_s, c.number? || -1}
        end
        sorted.each do |card|
          cardstr =
            Util.colorize(card.color_for_equality_test, "[#{card.to_s_short}]")+" "
          msg1 += cardstr
          msg2 += cardstr if card.can_put_on?(game.top_card)
        end
        if msg2.empty?
          msg2 = "(none)"
        end
        msg1 = "Your hand: " + msg1
        msg2 = "Playable cards: " + msg2
        return {msg1, msg2}
      end

      def pluralize(num : Int,
                    singular : String,
                    plural : String = singular+"s")
        return "#{num} " + (num == 1 ? singular : plural)
      end

      def colorize(msg)
        "\x0F#{msg}"
      end

      def colorize(color : Color, msg : String, bold = true)
        num = COLOR_NUMS[color]
        return String.build do |s|
          s << "\x02" if bold
          s << "\x03#{num.to_s.rjust(2,'0')}#{msg}\x0F"
          s << colorize("")
        end
      end
    end # module Util

    @chan : String?
    @user : String?
    @has_sudo : Bool = false
    @msg : FastIRC::Message?
    @pre : FastIRC::Prefix?

    def initialize(
          @command_prefix : String,
          @channels_to_join : Array(String),
          @server_name : String,
          @my_nick : String = "BetterUNOBot",
          @server_port : UInt16 = 6667u16,
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
        pre = fast_irc_msg.prefix
        next if pre.nil?

        if !@user.nil?
          STDERR.puts "@user was supposed to be nil, it wasn't"
          @user = nil
        end
        @chan = nil
        @msg = fast_irc_msg
        @pre = pre
        @has_sudo = false
        case fast_irc_msg.params.size
        when 1
          is_channel_msg = false
        when 2
          is_channel_msg = true
          @chan = fast_irc_msg.params.first
        else
          STDERR.puts "This is a weird server"
          next
        end
        message_text = fast_irc_msg.params.last
        @user = pre.source
        if message_text.starts_with? @command_prefix
          command_text = message_text[@command_prefix.size..-1]
          @command_handler.handle_command(command_text)
        end
        @user = nil
        @msg = nil
        @pre = nil
      end

      @irc.on("PART") do |msg|
        if msg.params.size == 0
          #TODO: return an error? It's invalid.
          next
        end

        chans = msg.params.first.split(',')

        if (pre = msg.prefix).nil? || pre.not_nil!.source == @my_nick
          #we're being told to leave. Or rather that we've already left.
          chans.each do |chan|
            # If games doesn't have a chan key, nothing happens
            @games.delete(chan)
          end
        else
          self.remove_player?(pre.not_nil!.source, chans)
        end
      end
      @irc.on("QUIT") do |msg|
        pre = msg.prefix
        next if pre.nil?
        self.remove_player?(pre.source)
      end
      @irc.on("NICK") do |msg|
        pre = msg.prefix
        next if pre.nil?
        next if msg.params.size != 1
        old_nick = pre.source
        new_nick = msg.params.first
        if old_nick == @my_nick
          @my_nick = new_nick
        else
          self.nick_change(old_nick, new_nick)
        end
      end

      @irc.on("001") do
        @channels_to_join.each do |channel_name|
          @irc.send FastIRC::Message.new("JOIN", [channel_name])
        end
      end

      @irc.on("PING") do |msg|
        @irc.send FastIRC::Message.new("PONG", msg.params)
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
        else
          cb.call(cmd)
        end
      end

      ch.make_wrapper :is_game_master do |cmd, cb|
        if !@games.has_key? chan
          reply "You've found a bug, this isn't supposed to happen"
        elsif user == game.players.first.name || @has_sudo
          cb.call(cmd)
        else
          reply "Only the Game Master #{game.players.first.name} may use this command. You do not have the power!"
        end
      end

      ch.make_wrapper :privileged do |cmd, cb|
        if @has_sudo
          cb.call(cmd)
        else
          reply "You do not have permission to use that command"
        end
      end

      ch.with_wrapper :privileged do
        ch.on "joinchan" do |cmd|
          if cmd.args.empty?
            reply "must provide argument"
            next
          end
          @irc.send FastIRC::Message.new("JOIN", [cmd.args.first])
        end
        ch.on "partchan" do |cmd|
          if cmd.args.empty?
            reply "must provide argument"
            next
          end
          @irc.send FastIRC::Message.new("PART", [cmd.args.first])
        end
        ch.on "sendraw" do |cmd|
          if cmd.args.empty?
            reply "must provide argument"
            next
          end
          puts "sending raw #{cmd.args.first.inspect}"
          @irc.send cmd.args.first
        end
        ch.on "asuserchan" do |cmd|
          if cmd.args.size < 3
            reply "must provide at least three arguments (user, channel, and command)"
            next
          end

          args = cmd.args.dup

          new_user = args.pop
          new_chan = args.pop
          old_sudo = @has_sudo
          old_user = @user
          old_chan = @chan

          @user = new_user
          @chan = new_chan
          @has_sudo = false
          new_cmd = Command.new(args[0], args[1..-1])
          @command_handler.handle_command(new_cmd)
          @user = old_user
          @chan = old_chan
          @has_sudo = old_sudo
        end
      end

      ch.on "sudo" do |cmd|
        if cmd.args.join(" ").downcase == "make me a sandwich"
          reply "Okay."
        elsif cmd.args.empty?
          reply "must provide argument"
        else
          if @pre.not_nil!.host == "enterprise.ncc-1701-D.captain"
            @has_sudo = true
            new_cmd = Command.new(cmd.args.first, cmd.args[1..-1])
            @command_handler.handle_command(new_cmd)
            @has_sudo = false
          else
            reply "You are not in the sudoers file. This incident will be reported."
          end
        end
      end

      ch.on "make" do |cmd|
        if cmd.args.join(" ").downcase == "me a sandwich"
          reply "do it yourself!"
        end
      end

      ch.on "make me a sandwich" do
        reply "do it yourself!"
      end

      ch.on "info", "help", "h", "?" do
        reply "I am the Better UNO Bot version #{UnoIrc::VERSION}, by jean-luc. Type '#{@command_prefix}uno' to start a new game. Source available at: https://github.com/captain-jean-luc/uno-irc"
      end

      ch.with_wrapper :in_channel do
        ch.on "suck my dick" do
          if chan.includes? "NSFW"
            reply "\x01ACTION sucks #{user}'s dick.\x01"
          else
            # do nothing
          end
        end
        ch.on "uno", "startuno", "unostart", "start" do
          if @games.has_key? chan
            reply "Game already started by #{game.players.first.name}! Type #{@command_prefix}"
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
                game.add_player(user)
                reply "#{user} has joined UNO! Game Master may type '#{@command_prefix}deal' to start the game"
              end
            end
            ch.on "deal", wrap: :is_game_master do
              game.deal
            end
            ch.on "end", "stop", "enduno", "stopuno", "unoend", "unostop", wrap: :is_game_master do
              game.end_game!
            end
            ch.on "hand", "state" do
              show_state user
            end
            ch.with_wrapper :is_current_player do
              ch.on "play", "p", /^p[^al]/ do |cmd|
                self.play_card(cmd)
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
            end # ch.with_wrapper :is_current_player do
          end # ch.with_wrapper :in_game do
        end # ch.with_wrapper :in_game do
      end # ch.with_wrapper :in_channel do
    end # def initialize(

    def start(loop_forever = true)
      @irc.connect


      # If the main Fiber finishes, all the other fibers are killed.
      # Since all the Important Stuff is happening in other fibers,
      # we have to keep this one running.
      # The caller can set loop_forever: false to take on that responsibility.
      if loop_forever
        loop{sleep 1}
      end
    end

    def play_card(cmd)
      puts "playing card #{cmd}"
      color      = nil
      number     = nil
      draw_num   = nil
      card_class = nil
      ambiguous_r_count = 0

      # Support commands like .p5 (with no space) instead of .p 5
      args = cmd.args.dup
      if cmd.name != "play"
        m = /\Ap(.+)/.match(cmd.name)
        if m && (extra = m[1]?)
          args.unshift(extra)
        end
      end

      args.each do |arg|
        # If someone does something like `.p "" ""` then there'll be no reply
        # but I don't care.
        if arg.size == 0 #empty string
          if args.size == 1 #this is the only argument
            reply "Ok, playing nothing. It's still your turn."
            return
          else
            #skip
            next
          end
        end

        case arg[0]
        when 'r'
          # Depending on the 3rd character or, if it doesn't exist, the second character...
          case (arg[2]? || arg[1]?)
          when 'd'
            color = Color::Red
          when 'v'
            card_class = Reverse
          when 'r' # "rr" is assumed to be Red Reverse
            color = Color::Red
            card_class = Reverse
          else #including 'e' or nil
            ambiguous_r_count += 1
          end
        when 'g'
          color = Color::Green
        when 'b'
          color = Color::Blue
        when 'y'
          color = Color::Yellow
        when 's'
          card_class = Skip
        when 'd'
          card_class = Draw if card_class.nil?
          m = /^d(raw)?(?<draw>[0-9]+)?/.match(arg)
          draw_num = m.try{|a| a["draw"]?.try(&.to_i)}
        when 'w'
          m = /^w(ild)?((d(raw)?)?(?<draw>[0-9]+))?/.match(arg)
          draw_num = (m.try{|n| n["draw"]?} || 0).to_i
          card_class = Wild
        when '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
          card_class = NumberCard
          number = arg[0].to_i
        else
          reply "@#{user} Unrecognized argument #{arg}, ignoring command."
          return
        end # case arg[0]
      end # args.each do

      playable_cards = player.hand.select do |card|
        card.can_put_on?(game.top_card)
      end

      if ambiguous_r_count == 1
        if (playable_cards.none?(&.is_a?(Reverse)) && card_class != Wild)
          # None of the playable cards are reverses, player must've meant color
          color = Color::Red
        elsif (playable_cards.none?{|c| c.color_for_equality_test == Color::Red || c.is_a?(Wild)})
          # No red cards, must've meant reverse
          card_class = Reverse
        elsif color.nil? && card_class.nil?
          reply "@#{user} Invalid play command, 'r' can be either red or reverse, use full names or 'rd' for red and 'rv' for reverse OR specify a color or card type, eg '#{@command_prefix}p r b' or '#{@command_prefix}p r s'"
          return
        elsif color.nil? # and card_class is not nil
          color = Color::Red
        elsif card_class.nil? # and color is not nil
          card_class = Reverse
        else # Both color and card_class are non-nil
          # They just threw in some "r"s for fun I guess?
          reply "@#{user} Did you throw in some extra \"r\"s just for fun?"
          return
        end
      elsif ambiguous_r_count >= 2
        color ||= Color::Red
        card_class ||= Reverse
      end # if ambiguous_r_count == 1

      # if ambiguous_r_count is zero, nothing needs to be done.

      if color.nil? && card_class.nil? && number.nil? && (playable_cards.size > 1)
        reply "@#{user} Which card do you want to play? Be more specific."
        return
      end

      pp color, card_class, number

      # Based on all the above criteria, find the first card that should be played
      card_idx = player.hand.index do |card|
        #puts card.inspect
        next false if card.is_a?(Wild) && card_class.nil?
        mc = (color.nil? || card.is_a?(Wild) || color == card.color_for_equality_test)
        mk = (card_class.nil? || card.class == card_class)
        md = (draw_num.nil? || (card.is_a?(DrawingCard) && card.draw == draw_num))
        mn = (number.nil? || (card.is_a?(NumberCard) && card.number == number))
        cp = card.can_put_on?(game.top_card)
        res = (mc && mk && md && mn && cp)
        next res
      end

      if card_idx.nil?
        reply "@#{user}, you cannot play or do not have that card."
        return
      end

      game.play(card_idx, color)
    end # def play_card(cmd)

    def handle_game_update(upd)
      puts "handling update #{upd.inspect}"
      case upd
      when Game::PlayerRemoved
        reply "#{upd.player.name} has left the game. Goodbye."
      when Game::Reversal
        reply "Play order reversed!"
      when Game::Skip
        reply "#{upd.player.name} is skipped!"
      when Game::Drew
        reply("#{upd.player.name} draws " +
              Util.pluralize(upd.howmany, "card") +
              ".")
        ho = Util.hand_of(upd.player, game)
        nreply(upd.player, ho[0])
        nreply(upd.player, ho[1])
      when Game::SkipDraw
        update_message =
          (upd.player.name +
           " " +
           (upd.forced ? "is forced to draw " : "draws ") +
           Util.pluralize(upd.howmany, "card") +
           " and is skipped!")
        reply update_message
        ho = Util.hand_of(upd.player, game)
        nreply(upd.player, ho[0])
      when Game::DrawDeckEmpty
        reply "The draw deck is empty! No cards drawn"
      when Game::DiscardToDraw
        reply("\x01ACTION "+
              Util.colorize(
                "takes all but the top card from the discard, " +
                 "and reshuffles to make a new draw pile") +
              "\x01")
      when Game::StartGame
        reply "GAME START"
      when Game::EndGame
        if upd.player.nil?
          reply "Game has ended."
        else
          reply "#{upd.player.not_nil!.name} has won!"
        end
        @games.delete(chan)
      when Game::Uno
        reply "UNO! #{upd.player.name} has one card left!"
      when Game::Turn
        show_state upd.player
      when Game::CommandError
        reply upd.message
      else
        reply "EVERYTHING IS ON FIRE THE WOLD IS A LIE ITS THE END TIMES"
      end # case upd
    end # def handle_game_update(

    def show_state(player : String)
      show_state(player: game.find_player(player).not_nil!)
    end

    def show_state(player : Player)
      top = game.top_card
      top_str = Util.colorize(top.color_for_equality_test, "[#{top.to_s_short}]")
      turn_name = game.current_player.name
      reply "#{turn_name}'s turn. Top card is #{top_str}."

      ho = Util.hand_of(player, game)
      nreply(player, ho[0])
      nreply(player, ho[1])

      playerstatus = game.next_players.map do |player|
        "#{player.name} - " + Util.pluralize(player.hand.size, "card")
      end
      nreply(player, "Next turns: " + playerstatus.join(" | "))
    end

    def remove_player?(username : String|Player, chans : Array(String)? = nil)
      if chans.nil?
        @games.each do |chan, game|
          game.del_player(username)
        end
      else
        chans.each do |chan|
          @games[chan]?.try(&.del_player(username))
        end
      end
    end

    def nick_change(old_name : String, new_name : String)
      @games.each do |channel_name, game|
        if (player = game.find_player(old_name))
          player.name = new_name
        end
      end
    end

    def chan
      @chan.not_nil!
    end

    def user
      @user.not_nil!
    end

    def player
      game.find_player(user).not_nil!
    end

    def game
      @games[chan]
    end

    def reply_target
      @chan || @user.not_nil!
    end

    def reply(msg : String)
      puts "replying with #{msg.inspect}"
      @irc.send( FastIRC::Message.new("PRIVMSG", [reply_target, msg]) )
    end

    def nreply(user : Player, msg : String)
      nreply(user.name, msg)
    end

    def nreply(user : String, msg : String)
      puts "nreply #{user},  #{msg.inspect}"
      @irc.send( FastIRC::Message.new("NOTICE", [user, msg]) )
    end
  end # class MainBot
end # module UnoIrc
