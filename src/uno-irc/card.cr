require "./color"
module UnoIrc
  module DrawingCard
    abstract def draw
    def draw?
      true
    end
  end

  module SkippingCard
    def skip?
      true
    end
  end
  
  abstract class Card
    property has_cum_on_it = false
    
    abstract def color : Color

    abstract def can_put_on?(other : Card) : Bool

    abstract def to_s_short

    def color_for_equality_test #created so that Wild can override
      self.color
    end

    def reset!
      #do nothing by default
    end
      
    def skip?
      false
    end

    def draw?
      false #self.responds_to?(:draw)
    end

    def to_s(io)
      self.class.to_s(io)
      io.print "<"
      color.to_s(io)
      io.print ", "
      io.print self.to_s_short
      io.print ">"
    end

    def number?
      nil
    end
  end

  class Wild < Card
    include DrawingCard
    include SkippingCard
    # A normal wild card with no skipdraw is @draw = 0
    getter draw
    @chosen_color : Color?
    def initialize(@draw = 0)
    end

    def can_put_on?(other)
      return true
    end

    def draw?
      return @draw != 0
    end

    def skip?
      draw?
    end

    def choose_color(c : Color)
      raise ArgumentError.new("Cannot be wild 'color'") if c == Color::Wild
      @chosen_color = c
    end

    def color
      @chosen_color.not_nil!
    end

    def color_for_equality_test
      @chosen_color || Color::Wild
    end

    def reset!
      @chosen_color = nil
    end

    def to_s_short
      "w" + (draw? ? "d#{draw}" : "")
    end

    def inspect
      "Wild#{draw}"
    end
  end

  abstract class NotWild < Card
    getter color
    def initialize(@color : Color)
    end

    def can_put_on?(other)
      other.color_for_equality_test == @color || other.class == self.class
    end

    def inspect
      "#{self.color}-#{self.class}"
    end
  end

  class Skip < NotWild
    include SkippingCard
    def to_s_short
      "s"
    end
    def inspect
      "#{self.color}-Skip"
    end
  end

  class Reverse < NotWild
    def to_s_short
      "r"
    end
    def inspect
      "#{self.color}-Reverse"
    end
  end

  class Draw < NotWild
    include DrawingCard
    include SkippingCard
    property draw
    def initialize(c, @draw = 2)
      super(c)
    end

    def to_s_short
      "d#{@draw}"
    end

    def inspect
      "Draw#{@draw}-#{color}"
    end
  end
  
  class NumberCard < NotWild
    property number
    def initialize(c, @number : Int32)
      super(c)
    end
    
    def can_put_on?(other)
      other.color_for_equality_test == @color || (other.is_a?(NumberCard) && other.number == @number)
    end

    def to_s_short
      @number.to_s
    end

    def inspect
      "#{color}-#{number}"
    end

    def number?
      number
    end
  end
end
    
