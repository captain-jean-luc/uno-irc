require "./card"

module UnoIrc
  class Deck < Array(Card)
    def self.default_fill
      d = self.new()
      4.times do
        d << Wild.new
        d << Wild.new(4)
      end

      Color.each do |c|
        next if c == Color::Wild

        d << NumberCard.new(c, 0)
        
        2.times do
          d << Skip.new(c)
          d << Reverse.new(c)
          d << Draw.new(c)

          (1..9).each do |n|
            d << NumberCard.new(c, n)
          end
        end
      end
      return d
    end

    def add_values_from(other : Enumerable(Card))
      other.each do |card|
        self << card
      end
    end
  end
end
