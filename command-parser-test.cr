require "./src/uno-irc/command-handler"

macro test(input, chan)
  p {{input}}
  puts {{input}}
  puts "----"
  p ch.handle_command({{input}}, {chan: {{chan}}, nick: "bob"})
  puts "----------------"
end

macro test(input)
  puts "in privmsg"
  test({{input}}, "bob")
  puts "in channel"
  test({{input}}, "#some_channel")
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

ch = UnoIrc::CommandHandler({chan: String, nick: String}).new

ch.on_invalid do |cmd, info|
  puts "Invalid command! #{cmd.inspect}"
end

ch.make_wrapper(:in_channel) do |cmd, args, info, cb|
  if info[:chan] == info[:nick] || info[:chan].empty?
    puts "Tried to execute #{cmd.inspect} #{args.inspect} but not in a channel"
  else
    cb.call(args, info)
  end
end

ch.make_wrapper(:no_args) do |cmd, args, info, cb|
  if args.empty?
    cb.call(args, info)
  else
    puts "#{cmd} takes no arguments"
  end
end

ch.on "help" do
  puts "Help command called"
end

ch.on " ", :no_args do
  puts "SPAAAAAAAAACE"
end

ch.on "printargs" do |args, info|
  pp args
end

ch.with_wrapper :in_channel do
  ch.on "print channel name", :no_args do |args, info|
    puts info[:chan]
  end

  ch.on "printall" do |args, info|
    pp args, info
  end
end

test "help"

test "  oh my what big ears you have"

test "\"print channel name\""

test "\"print channel name\" right now!"

test "printargs 1 2 3 bla:bloopalquintecafrankles"

test "printall"
