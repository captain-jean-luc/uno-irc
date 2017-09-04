require "./deck"
require "CrystalIrc"

module UnoIrc
  class Player < CrystalIrc::Target
    def initialize(@name : String)
      @hand = Deck.new
    end

    getter hand
    property name
  end
end
