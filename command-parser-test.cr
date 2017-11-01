require "./src/uno-irc/command-handler"

macro test(awesome_input, chan)
  p {{awesome_input}}
  puts {{awesome_input}}
  puts "----"
  p ch.handle_command({{awesome_input}}, {chan: {{chan}}, nick: "bob"}.to_h)
  puts "----------------"
end

macro test(awesome_input)
  puts "in privmsg"
  test({{awesome_input}}, "bob")
  puts "in channel"
  test({{awesome_input}}, "#some_channel")
end

if false
  pp UnoIrc::CommandParser.parse("")
  pp UnoIrc::CommandParser.parse(" ")
  pp UnoIrc::CommandParser.parse("help")
  pp UnoIrc::CommandParser.parse("help halp")
  pp UnoIrc::CommandParser.parse("\"help halp\"")
  pp UnoIrc::CommandParser.parse(" things and stuff")
  pp UnoIrc::CommandParser.parse("  things and stuff")
end
#test "I am a donkey"
#test "What\tdid you say about me boi?"
#test ""
#test " "
#test "  hey dere "
#test "\\"
#test "\\\\"
#test "command arg:\"value\" stuff"
#test %{Username "blargedy \\\\ boop \\\" balls " of awesome}

ch = UnoIrc::CommandHandler.new#({chan: String, nick: String}).new

ch.on_invalid do |cmd, info|
  puts "Invalid command! #{cmd.inspect}"
end

ch.make_wrapper(:in_channel) do |cmd, args, info, cb|
  puts ":in_channel wrapper is running"
  if info[:chan] == info[:nick] || info[:chan].empty?
    puts "Tried to execute #{cmd.inspect} #{args.inspect} but not in a channel"
  else
    cb.call(args, info)
  end
  puts ":in_channel wrapper finished"
end

ch.make_wrapper(:no_args) do |cmd, args, info, cb|
  puts ":no_args wrapper START"
  if args.empty?
    cb.call(args, info)
  else
    puts "#{cmd} takes no arguments"
  end
  puts ":no_args wrapper END"
end

ch.on "help" do
  puts "Help command called"
end

ch.on " ", wrap: :no_args do
  puts "SPAAAAAAAAACE"
end

ch.on "printargs" do |args, info|
  pp args
end

ch.with_wrapper :in_channel do
  ch.on "print channel name", wrap: :no_args do |args, info|
    puts info[:chan]
  end

  ch.on "printall" do |args, info|
    pp args, info
  end
end

#test "help"

#test "help help halp holp"

test "  oh my what big ears you have"

test "  space with args"

test "\"print channel name\""

test "\"print channel name\" right now!"

test "printargs 1 2 3 bla:bloopalquintecafrankles"

test "printall"
