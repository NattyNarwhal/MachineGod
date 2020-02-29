defmodule MachineGod.IrcParser do
  @doc ~S"""
  Determines if a string is a channel name.

  ## Examples

      iex> MachineGod.IrcParser.is_channel?("#test")
      true

  """
  def is_channel?(target) do
    String.first(target) in ["#", "&"]
  end

  @doc ~S"""
  Extracts the nick from a string, or returns the string otherwise.

  ## Examples

      iex> MachineGod.IrcParser.simple_name("foo!bar@xyzzy")
      "foo"
      iex> MachineGod.IrcParser.simple_name("irc.freenode.net")
      "irc.freenode.net"

  """
  def simple_name(from) do
    if String.contains?(from, "!") and String.contains?(from, "@") do
      {nick, ident, host} = split_name(from)
      nick
    else
      from
    end
  end

  @doc ~S"""
  Converts an IRC ident and hostmask into a tuple.

  ## Examples

      iex> MachineGod.IrcParser.split_name("foo!bar@xyzzy")
      {"foo", "bar", "xyzzy"}

  """
  def split_name(from) do
    [nick, ident_host] = from
      |> String.split("!", [ parts: 2 ])
    [ident, host] = ident_host
      |> String.split("@", [ parts: 2 ])
    {nick, ident, host}
  end

  @doc ~S"""
  Takes the nick from /NAMES and extracts into a tuple of rank and user.

  ## Examples

      iex> MachineGod.IrcParser.names_parse("@foo")
      {:operator, "foo"}
      iex> MachineGod.IrcParser.names_parse("bar")
      {:user, "bar"}

  """
  def names_parse(name) do
    case name do
      "~" <> user ->
        {:founder, user}
      "&" <> user ->
        {:protected, user}
      "@" <> user ->
        {:operator, user}
      "%" <> user ->
        {:halfop, user}
      "+" <> user ->
        {:voice, user}
      _ ->
        {:user, name}
    end
  end

  defp parse_command_no_colon(line) do
    split = String.split(line)
    case split do
      ["PING", cookie] ->
        {:ping, cookie}
    end
  end

  defp get_trailer_inner(chunks) do
    chunks |> List.last
  end

  defp get_trailer(chunks) do
    chunks
      |> after_command_message
      |> List.last
  end

  defp get_targeted_message(chunks) do
    from = hd(chunks)
    # This is the first argument after the command.
    chunks_inner = after_command_message(chunks)
    to = chunks_inner
      |> List.first
      |> String.split
      |> hd
    message = get_trailer_inner(chunks_inner)
    {from, to, message}
  end

  defp after_command_message(chunks) do
    chunks
      |> List.last
      |> String.split(":", [ parts: 2 ])
  end

  defp parse_command_colon(line) do
    # The format varies a lot. Sometimes there is a trailer, sometimes not.
    chunks = line
      # Get the source, command, and then leave the rest alone.
      |> String.split(":", [ parts: 2 ])
      |> List.last
      |> String.split(" ", [ parts: 3 ])
    # chunks = [ source, command, rest of line ]
    # Because the rest of the line is variable, it must be parsed per-command.
    case tl(chunks) do
      ["001" | _] ->
        {:welcome, get_trailer(chunks) }
      ["002" | _] ->
        {:yourhost, get_trailer(chunks) }
      ["003" | _] ->
        {:created, get_trailer(chunks) }
      ["004", message] ->
        # After the command, it's the target nick, then the message contents
        supports = message
          |> String.split
          |> tl # remove nick
        {:myinfo, supports}
      ["005", message] ->
        supports = message
          |> String.split
          |> tl # remove nick
          # Hacky way to remove the trailer, since we can't split from the end
          # and chunks in this can contain colons.
          |> Enum.take_while(fn x -> not String.starts_with?(x, ":") end)
        {:isupport, supports}
      ["250" | _] ->
        {:statsdline} # XXX
      ["251" | _] ->
        {:luserclient}
      ["252", message] ->
        [_, ops | _] = message # ignore the trailer with ignored tail
          |> String.split # and ignore the target
        {:luserop, String.to_integer(ops)}
      ["253", message] ->
        [_, ops | _] = message
          |> String.split
        {:luserunknown, String.to_integer(ops)}
      ["254", message] ->
        [_, channels | _] = message
          |> String.split
        {:luserchannels, String.to_integer(channels)}
      ["255" | _] ->
        {:luserme}
      ["265", message] ->
        [_, users, max | _] = message
          |> String.split
        {:localusers, String.to_integer(users), String.to_integer(max)}
      ["266", message] ->
        [_, users, max | _] = message
          |> String.split
        {:globalusers, String.to_integer(users), String.to_integer(max)}
      ["324", message] ->
        [_, channel | modes] = message |> String.split
        {:channelmodeis, channel, modes}
      ["329", message] ->
        [_, channel, who] = message |> String.split
        # XXX: Convert epoch to Elixir Time?
        {:creationtime, channel, who}
      ["332" | _] ->
        [first, trailer] = after_command_message(chunks)
        [_, channel] = first |> String.split
        {:topic, channel, trailer}
      ["333", message] ->
        [_, channel, who, time] = message |> String.split
        # XXX: Convert epoch to Elixir Time?
        {:topicwhowhen, channel, who, time}
      ["353" | _] ->
        [first, trailer] = after_command_message(chunks)
        [_, type, channel] = first |> String.split
        users = trailer |> String.split
        {:namreply, type, channel, users}
      ["366" | _] ->
        [first, _] = after_command_message(chunks)
        [_, channel] = first |> String.split
        {:endofnames, channel}
      ["372" | _] ->
        {:motd, get_trailer(chunks) }
      ["375" | _] ->
        {:motdstart, get_trailer(chunks) }
      ["376" | _] ->
        {:endofmotd, get_trailer(chunks) }
      ["396" | _] ->
        [first, _] = after_command_message(chunks)
        [_, host] = first |> String.split
        {:hosthidden, host}
      ["421", message] ->
        [_, command] = message
          |> String.split # it's ok to ignore trailer
        {:unknowncommand, command}
      ["433", message] ->
        [original_nick, new_nick] = message
          |> String.split(":", [ parts: 2 ])
          |> List.first
          |> String.split
        {:nicknameinuse, original_nick, new_nick}
      ["NICK", _] ->
        {:nick, hd(chunks), get_trailer(chunks)}
      ["NOTICE", _] ->
        {from, to, message} = get_targeted_message(chunks)
        {:notice, from, to, message}
      ["TOPIC", _] ->
        {from, to, message} = get_targeted_message(chunks)
        {:topic, from, to, message}
      ["PRIVMSG", _] ->
        {from, to, message} = get_targeted_message(chunks)
        {:privmsg, from, to, message}
      ["MODE", _] ->
        {from, to, message} = get_targeted_message(chunks)
        {:mode, from, to, message}
      ["KICK", _] ->
        [first, message] = after_command_message(chunks)
        [channel, to] = first |> String.split
        {:kick, hd(chunks), to, channel, message}
      ["PART", _] ->
        {from, to, message} = get_targeted_message(chunks)
        {:part, from, to, message}
      ["QUIT", _] ->
        {:quit, hd(chunks), get_trailer(chunks)}
      ["JOIN", _] ->
        {:join, hd(chunks), get_trailer(chunks)}
    end 
  end

  defp parse_command(line) do
    case line do
      ":" <> _ ->
        parse_command_colon(line)
      _ ->
        parse_command_no_colon(line)
    end
  end

  def parse_line(line) do
    line
      |> String.trim_trailing("\n" )
      |> String.trim_trailing("\r")
      |> parse_command
  end
end
