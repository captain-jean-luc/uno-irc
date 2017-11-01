require "./uno-irc/*"
require "./fast_irc_wrapper.cr"

struct FastIRC::Message # Some monkey-patching
  def params
    res = previous_def
    if res.nil?
      return [] of String
    else
      return res
    end
  end

  def prefix
    previous_def.not_nil!
  end
end

module UnoIrc
  COLOR_NUMS = {
    Color::Red => 4,
    Color::Green => 3,
    Color::Blue => 12,
    Color::Yellow => 8,
    Color::Wild => 0
  }

  CMD_PREFIX = "."
    
  @@games = {} of String => Game

  def self.pluralize(num : Int, singular : String, plural : String = singular+"s")
    return "#{num} " + (num == 1 ? singular : plural)
  end
  
  def self.colorize(msg)
    "\x0300,01#{msg}"
  end

  def self.colorize(color : Color, msg : String, bold = true)
    num = COLOR_NUMS[color]
    return (bold ? "\x02" : "") + "\x03#{num.to_s.rjust(2,'0')},01#{msg}" + "\x0F" + colorize("")
  end

  def self.hand_of(player : Player, game : Game)
    msg1 = "" #"Your hand: "
    msg2 = "" #"Playable cards: "
    sorted = player.hand.sort_by{|c| {c.color_for_equality_test, c.class.to_s, c.number? || -1} }
    sorted.each do |card|
      cardstr = colorize(card.color_for_equality_test, "[#{card.to_s_short}]")+" "
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

  macro s(msg)
    sender.privmsg(channel, colorize({{msg}}))
  end
  macro np(nick, msg)
    %var = ({{nick}})
    if %var.responds_to?(:name)
      %send_to = %var.name
    else
      %send_to = %var
    end
    sender.notice(%send_to, colorize({{msg}}))
  end

  def self.update_handler_maker(sender : FastIRCWrapper, channel : String, game : Game)
    return ->(upd : UnoIrc::Game::Update) do
      case upd
      when Game::PlayerRemoved
        s("#{upd.player.name} has left the game. Goodbye.")
      when Game::Reversal
        s "Play order reversed!"
      when Game::Skip
        s "#{upd.player.name} is skipped!"
      when Game::Drew
        s "#{upd.player.name} draws " + self.pluralize(upd.howmany, "card") + "."
        ho = self.hand_of(upd.player, game)
        np(upd.player, ho[0])
        np(upd.player, ho[1])
      when Game::SkipDraw
        update_message = (upd.player.name + " " + (upd.forced ? "is forced to draw " : "draws ") + self.pluralize(upd.howmany, "card") + " and is skipped!")
        s update_message
        ho = self.hand_of(upd.player, game)
        np(upd.player, ho[0])
      when Game::DrawDeckEmpty
        s "The draw deck is empty! No cards drawn"
      when Game::DiscardToDraw
        sender.privmsg channel, "\x01ACTION " + colorize("takes all but the top card from the discard, and reshuffles to make a new draw pile") + "\x01"
      when Game::StartGame
        s "GAME START"
      when Game::EndGame
        if upd.player.nil?
          s "Game has ended."
        else
          s "#{upd.player.not_nil!.name} has won!"
        end
        @@games.delete(channel)
      when Game::Uno
        s "UNO! #{upd.player.name} has one card left!"
      when Game::Turn
        top = game.top_card
        top_str = colorize(top.color_for_equality_test, "[#{top.to_s_short}]")
        if upd.match
          s "Match! It is #{upd.player.name}'s turn again. Top card is #{top_str}."
        else
          s "#{upd.player.name}'s turn. Top card is #{top_str}."
        end

        player = upd.player
        ho = self.hand_of(player, game)
        np(player, ho[0])
        np(player, ho[1])

        playerstatus = game.next_players.map do |player|
          "#{player.name} - " + self.pluralize(player.hand.size, "card")
        end
        np(player.name, "Next turns: " + playerstatus.join(" | "))
      end

      return nil
    end
  end

  def self.respond_to(chan : String, nick : String, full_command : Array(String), sender, msg) : String?
    pp chan, nick, full_command
    command = full_command[0]
    args = full_command[1..-1]


    nilgame = nil
    
    is_current_player = Proc(String | Player).new do
      player = nilgame.not_nil!.find_player(nick)
      if player.nil?
        return "@#{nick}, you're not in the game. Sorry."
      end
      if player != nilgame.not_nil!.current_player
        return "@#{nick}, it's not your turn. Just hold on a sec, okay?"
      end
      return player
    end

    if !chan.nil?
      nilgame = (@@games[chan]?)
      pp command

      if nick == "jean-luc" || nick == "jean"
        pp msg
      end
      case command.downcase
      when "info", "help", "h", "?"
        return "I am the Better UNO Bot version #{UnoIrc::VERSION}, by jean-luc. Type '#{CMD_PREFIX}uno' to start a new game. Source available at: https://github.com/captain-jean-luc/uno-irc"
      when "uno", "startuno", "unostart", "start"
        if !nilgame.nil?
          return "Game already started by #{nilgame.not_nil!.players.first.name}! Type '#{CMD_PREFIX}join' to join!"
        end
        nilgame = @@games[chan] = Game.new
        game = nilgame.not_nil!
        game.on_update &self.update_handler_maker(sender, chan, game)
        game.add_player(nick)
        return "Game started! Type '#{CMD_PREFIX}join' to join!"
      end
      begin
        return("No game started, try '#{CMD_PREFIX}uno' to create a game") if nilgame.nil?
        game = nilgame.not_nil!
        if (command[0]? == 'd' && command != "deal" && command != "draw")
          if game.started
            command = "draw"
          else
            command = "deal"
          end
        end
        case command.downcase
        when "ujoin", "unojoin", "join", "j", "joinuno", "uj"
          if game.players.any?{|p| p.name == nick}
            return "@#{nick}, you've already joined!"
          end
          game.add_player(nick)
          return "#{nick} has joined UNO! Game master may type '#{CMD_PREFIX}deal' to start the game"
        when "deal"
          if nick != game.players.first.name
            return "@#{nick}, only the ultimate god #{game.players.first.name} can deal. You do not have the power!"
          end
          game.deal
        when "play", "p", /\Ap[^a]/
          player_or_error = is_current_player.call
          return "#{player_or_error}" if player_or_error.is_a? String
          player = player_or_error
          #if args.empty?
          #  return "@#{nick}, not enough arguments"
          #end
          color = nil
          number = nil
          draw_num = nil
          card_class = nil
          ambiguous_r_count = 0

          m = /\Ap(.+)/.match(command)
          if m && (m = m[1]?)
            args.unshift(m)
          end
          args.each do |arg|
            if arg.size == 0
              return "You *almost* found a bug, keep trying!"
            end
            arg = arg.downcase
            case arg[0].to_s
            when "r"
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
            when "g"
              color = Color::Green
            when "b"
              color = Color::Blue
            when "y"
              color = Color::Yellow
            when "s"
              card_class = Skip
            when "d"
              card_class = Draw if card_class.nil?
              m = /^d(raw)?(?<draw>[0-9]+)?/.match(arg)
              draw_num = m.try{|a| a["draw"]?.try(&.to_i)}
            when "w"
              m = /^w(ild)?((d(raw)?)?(?<draw>[0-9]+))?/.match(arg)
              draw_num = (m.try{|n| n["draw"]?} || 0).to_i
              card_class = Wild
            #color = Color::Wild
            when /[0-9]/
              card_class = NumberCard
              number = arg[0].to_i
            else
              return "@#{nick} Unrecognized argument #{arg}, ignoring command."
            end
          end

          playable_cards = player.hand.select do |card|
            card.can_put_on?(game.top_card)
          end
          
          if ambiguous_r_count == 1
            #if color.nil? && card_class == Wild
            #  color == Color::Red
            if (playable_cards.none?(&.is_a?(Reverse)) && card_class != Wild)
              # None of the playable cards are reverses, player must've meant color
              color = Color::Red
            elsif (playable_cards.none?{|c| c.color_for_equality_test == Color::Red})
              # No red cards, must've meant type
              card_class = Reverse
            elsif color.nil? && card_class.nil?
              return "@#{nick} Invalid play command, 'r' can be either red or reverse, use full names or 'rd' for red and 'rv' for reverse OR specify a color or card type, eg '#{CMD_PREFIX}p r b' or '#{CMD_PREFIX}p r s'"
            elsif color.nil? # and card_class is not nil
              color = Color::Red
            elsif card_class.nil? # and color is not nil
              card_class = Reverse
            else
              #They just threw in some "r"s for fun I guess?
              return "@#{nick} Did you throw in some extra \"r\"s just for fun?"
            end
          elsif ambiguous_r_count >= 2
            color ||= Color::Red
            card_class ||= Reverse
          end
          if color.nil? && card_class.nil? && number.nil? && (playable_cards.size > 1)
            return "@#{nick} Which card do you want to play? Be more specific."
          end

          #pp color, card_class, draw_num, number
          
          # Based on all the above criteria, find the first card that should be played
          card_idx = player.hand.index do |card|
            #puts card.inspect
            next false if card.is_a?(Wild) && card_class.nil?
            mc = (color.nil? || card.is_a?(Wild) || color == card.color_for_equality_test)
            mk = (card_class.nil? || card.class == card_class)
            md = (draw_num.nil? || (card.is_a?(DrawingCard) && card.draw == draw_num))
            mn = (number.nil? || (card.is_a?(NumberCard) && card.number == number))
            cp = card.can_put_on?(game.top_card)
            #puts
            res = (mc && mk && md && mn && cp)
            #puts
            next res
          end

          #pp card_idx
          
          if card_idx.nil?
            return "@#{nick}, you cannot play or do not have that card."
          end

          if color.nil?
            game.play(card_idx)
          else
            game.play(card_idx, color)
          end
        when "draw"
          player = is_current_player.call
          return "#{player}" if player.is_a? String
          game.voluntary_draw
        when "drawpass", "dp"
          player = is_current_player.call
          return "#{player}" if player.is_a? String
          game.drawpass
        when "pass", "pa"
          player = is_current_player.call
          return "#{player}" if player.is_a? String
          game.pass
        when "end","stop","enduno","stopuno","unoend","unostop"
          if nick != game.players.first.name
            return "@#{nick}, only the ultimate god #{game.players.first.name} can End The Game. You do not have the power!"
          end
        else
          return "Unrecognized command #{CMD_PREFIX}#{command}"
        end
      rescue ex : Game::CommandError
        return "#{ex.message}"
      end
    else
      return("All commands must be used within a channel.")
    end
    return nil
  end

#  macro reply(msg_str)
#    msg.reply self.colorize({{msg_str}})
#  end

  def self.start
    bot = FastIRCWrapper.new server: "irc.rizon.net", nick: "BetterUNOBot2", port: 6667_u16, ssl: false

    bot.on_message do |msg|
      msg.to_s(STDOUT)
    end

    # Kill switch, just in case
    bot.on("PRIVMSG") do |msg|
      if msg.params.last.starts_with? "DIEUNODIE"
        begin
          STDERR.puts "Received killswitch, #{msg.inspect}"
        ensure
          exit 1
        end
      end
    end
    
    bot.on("PRIVMSG") do |fast_irc_msg|
      channel_name = ""
      case fast_irc_msg.params.size
      when 1
        is_channel_msg = false
      when 2
        is_channel_msg = true
        channel_name = fast_irc_msg.params.first
      else
        STDERR.puts "This is a weird server"
      end
      message_text = fast_irc_msg.params.last
      nick = fast_irc_msg.prefix.source
      msg = Message.new(channel_name, nick, message_text, bot)
      if message_text.starts_with? CMD_PREFIX
        full_command = message_text[1..-1].split(/\s+/) #the message sans the command prefix, split on whitespace.
        response = self.respond_to(channel_name, nick, full_command, sender: bot, msg: msg)
        if response
          msg.reply response
        end
      end
    end

    bot.on("PART") do |msg|
      self.remove_player?(msg)
    end
    bot.on("QUIT") do |msg|
      self.remove_player?(msg)
    end
    bot.on("NICK") do |msg|
      self.nick(msg)
    end
    
    bot.on("001") do
      bot.send FastIRC::Message.new("JOIN", ["#betterbottest"])
    end

    bot.on("PING") do |msg|
      bot.send( FastIRC::Message.new("PONG", msg.params) )
    end

    bot.connect

    loop do
      sleep 1
    end
  end

  def self.test
    results = [] of Int32
    1_000_000.times do |i|
      puts i if i % 1000 == 0
      game = Game.new do |upd|
        next
        if upd.is_a?(Game::Turn)
          puts "#{upd.player.name}'s turn, top is #{upd.top.inspect}"
        else
          pp upd
        end
      end
      #pp game.nodraw
      p1 = Player.new "Bob"
      p2 = Player.new "Joe"
      p3 = Player.new "Bill"
      p4 = Player.new "Chris"
      game.add_player(p1)
      game.add_player(p2)
      game.add_player(p3)
      game.add_player(p4)
      game.deal
      #pp game.nodraw
      while game.started
        played = false
        #pp game.current_player.name
        p = game.current_player
        if p.hand.empty?
          puts "EMPTY"
          exit 1
        end
        p.hand.each_index do |i|
          if game.can_play?(i)
            #puts "#{p.name} Playing #{game.current_player.hand[i].inspect}"
            game.play(i, Color::Red)
            played = true
            break
          end
        end
        if !played
          #puts "#{p.name} Passing turn"
          game.drawpass
        end
        #puts "----------"
      end
      #pp game.turn_counter
      results << game.turn_counter
    end
    #puts results
    pp results.size
    pp results.minmax, results.sum.to_f/results.size
  end

  def self.remove_player?(msg)
    nick = msg.prefix.source
    @@games.each do |channel_name, game|
      game.del_player(nick) if game.players.any?{|p| p.name == nick}
    end
  end

  def self.nick(msg)
    new_name = msg.params.last
    old_name = msg.prefix.source
    pp old_name, new_name
    @@games.each do |channel_name, game|
      puts "found game #{channel_name}"
      if (player = game.find_player(old_name))
        puts "found player"
        player.name = new_name.not_nil!
        puts "player name is now #{player.name}"
      end
    end
  end
end

UnoIrc.start
