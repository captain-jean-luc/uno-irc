require "./uno-irc/*"

bot = UnoIrc::MainBot.new(
  command_prefix: ".",
  channels_to_join: ["#betterbottest", "#tulpa.NSFW"],
  my_nick: "BetterUNOBot",
  server_name: "irc.rizon.net"
)

bot.start
