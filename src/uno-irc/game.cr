require "./deck"
require "./player"

module UnoIrc
  class Game
    abstract struct Update
    end
    struct PlayerRemoved < Update
      getter player
      def initialize(@player : Player)
      end
    end
    struct Reversal < Update; end
    struct Skip < Update
      getter player
      def initialize(@player : Player)
      end
    end
    abstract struct DrawnCardsAbstractUpdate < Update
      getter player, howmany, forced
      def initialize(@player : Player, @howmany : Int32, @forced : Bool)
      end
    end
    struct Drew < DrawnCardsAbstractUpdate ; end
    struct SkipDraw < DrawnCardsAbstractUpdate; end
    struct DrawDeckEmpty < Update
      #This only happens if no cards were available from the discard pile
    end
    struct DiscardToDraw < Update
      #When the cards in the discard are transferred to draw pile because the draw was empty
    end
    struct StartGame < Update
      getter players
      def initialize(@players : Array(Player))
      end
    end
    struct EndGame < Update
      #If player is nil then nobody, this was caused by too few people or something
      getter player
      def initialize(@player : Player?)
      end
    end
    struct Uno < Update
      getter player
      def initialize(@player : Player)
      end
    end
    struct Turn < Update
      getter player, top, match
      def initialize(@player : Player, @top : Card, @match : Bool = false)
      end
    end
    struct NotEnoughCards < Update
      getter dealt
      def initialize(@dealt : Int32)
      end
    end
    struct CommandError < Update
      getter message
      def initialize(@message : String)
      end
    end

    #class CommandError < Exception
    #end

    @players : Array(Player)
    @current_player_idx = 0
    @direction_bool = true #to handle reverse cards
    @on_update : Update ->
    @draw : Deck
    @discard : Deck
    @started = false
    @turn_counter = 0

    @has_drawn = false

    getter started, turn_counter, players

    def initialize(@players = [] of Player, @draw = Deck.default_fill, &@on_update)
      @discard = Deck.new
    end

    def initialize(@players = [] of Player, @draw = Deck.default_fill)
      @discard = Deck.new
      @on_update = ->(a : Update){}
    end

    def on_update(&block : Update ->)
      @on_update = block
    end

    def deal
      cmderr "Already started!" if @started
      cmderr "Not enough players!" if @players.size < 2
      cmderr "Not even a single card!" if @draw.empty?
      @draw.shuffle!
      @discard << @draw.pop
      if (c = top_card).is_a? Wild
        c.choose_color NonwildColors.sample
      end
      7.times do |card_i|
        if @draw.size < @players.size
          if card_i == 0
            cmderr "Not enough cards in the deck! Increase the number of cards or decrease the number of players"
          else
            event NotEnoughCards.new(card_i)
            break
          end
        end
        @players.each do |player|
          player.hand << @draw.pop
        end
      end
      @current_player_idx = rand(@players.size)
      @started = true
      event StartGame.new(@players)
      event Turn.new(current_player, self.top_card)
    end

    def add_player(playername : String)
      add_player Player.new playername
    end

    def add_player(player : Player)
      cmderr "Game already started!" if @started
      @players << player
    end

    def find_player_idx(name : String)
      return @players.index{|player| player.name == name}
    end

    def find_player(name : String)
      idx = find_player_idx(name)
      return nil if idx.nil?
      return @players[idx]
    end

    def del_player(name : String)
      player_idx = find_player_idx(name)
      if player_idx.nil?
        STDERR.puts "WARN: tried to delete non-existant player #{name.inspect}"
      else
        del_player player_idx
      end
    end

    def del_player(idx : Int)
      next_player! if @current_player_idx == idx && @started
      deleted_player = @players.delete_at(idx)
      @current_player_idx -= 1 if @current_player_idx > idx && @started
      event PlayerRemoved.new(deleted_player)
      end_game! if @players.size < 2 && @started #need at least 2 ppl to play
    end

    def current_player
      @players[@current_player_idx]
    end

    def top_card
      @discard.last
    end

    def can_play?(card_idx, player = current_player)
      return false if !@started
      return player.hand[card_idx].can_put_on? top_card
    end

    def draw_one?(player = current_player)
      assert_started!
      if @draw.empty?
        # empty all but the top card from discard and shuffle
        new_cards = @discard.delete_at(0,@discard.size - 1)
        if new_cards.empty?
          event DrawDeckEmpty.new()
          return false #no cards left to draw
        end
        new_cards.shuffle!
        new_cards.each(&.reset!)
        event DiscardToDraw.new()
        @draw.add_values_from new_cards
      end
      #at this point, @draw is garunteed to at least have one card
      player.hand << @draw.pop
      return true
    end

    def draw?(how_many, player = current_player, skipdraw = false, forced = skipdraw)
      assert_started!
      drawn = 0
      how_many.times do |i| #have to tell you, you can't go past warp 10! Otherwise we'll become space lizards.
        if draw_one?(player)
          drawn += 1
        else
          break
        end
      end
      if skipdraw
        event SkipDraw.new(player, drawn, forced)
      else
        event Drew.new(player, drawn, forced)
      end
      return drawn
    end

    def voluntary_draw
      if @has_drawn
        cmderr "You can only draw once per turn"
      else
        draw? 1, forced: false
        @has_drawn = true
      end
    end

    def drawpass
      #assert_started is handled by the draw? method
      p = current_player
      how_many = draw? 1, forced: false, player: p
      last_idx = p.hand.size - 1
      if how_many == 0
        pass
        return
      end
      drawn_card = p.hand[last_idx]
      if drawn_card.can_put_on?(top_card)
        if drawn_card.is_a? Wild
          #let the player decide what to do
          return
        end
        play(last_idx, player: p)
      else
        pass
      end
    end

    def pass
      assert_started!
      next_player!
      event Turn.new(current_player, top_card)
    end

    def play(card_idx, colorpick = nil, player = current_player) : Nil
      assert_started!
      cmderr "Cannot play that card" unless can_play?(card_idx)
      card = player.hand[card_idx]
      if card.is_a? Wild
        cmderr "Must provide a color" if colorpick.nil?
        cmderr "Not a valid color" if colorpick == Color::Wild
        card.choose_color( colorpick.not_nil! )
      end
      @turn_counter += 1
      player.hand.delete_at(card_idx)
      if player.hand.empty?
        end_game(player)
        return
      elsif player.hand.size == 1
        event Uno.new(player)
      end
      @discard << card
      reverse_is_skip = @players.size == 2
      if card.skip? || (reverse_is_skip && card.is_a? Reverse)
        next_player!
        skipped_player = current_player
        event Skip.new(skipped_player) if !card.draw?
      end
      # Both checks are required, the first so that crystal doesn't complain about types,
      # The second to check if the card causes drawing when it's a wild card
      if card.is_a?(DrawingCard) && card.draw? && !skipped_player.nil?
        num_drawn = draw?(card.draw, skipped_player, skipdraw: true)
        #event SkipDraw.new(skipped_player, num_drawn)
      end
      if !reverse_is_skip && card.is_a? Reverse
        @direction_bool = !@direction_bool
        event Reversal.new
      end

      #all done, move to the next player
      pass
    end

    def next_player! : Nil
      assert_started!
      if @direction_bool
        @current_player_idx += 1
      else
        @current_player_idx -= 1
      end
      @current_player_idx %= @players.size
      @has_drawn = false
    end

    def end_game!
      end_game nil
    end

    def end_game(player_name : String)
      end_game(find_player(player_name))
    end

    def end_game(player : Player?)
      assert_started!
      @started = false
      event EndGame.new(player)
    end

    def next_players
      Array(Player).new(@players.size - 1) do |i|
        if @direction_bool
          new_idx = @current_player_idx + (i + 1)
        else
          new_idx = @current_player_idx - (i + 1)
        end
        new_idx %= @players.size
        @players[new_idx]
      end
    end

    # FOR DEBUGGING/DISPLAY PURPOSES ONLY
    def empty_draw!
      @draw = Deck.new
    end

    # FOR DEBUGGING/DISPLAY PURPOSES ONLY
    def nodraw
      new = self.dup
      new.empty_draw!
      return new
    end

    private def event(update)
      @on_update.call(update)
    end

    private macro cmderr(string)
      event CommandError.new({{string}})
      return
    end

    private def assert_started!
      cmderr "Game has not started yet" unless @started
    end
  end
end
