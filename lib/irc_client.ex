defmodule MachineGod.IrcClient do
  use GenServer

  defp send_line(client, line) do
    :gen_tcp.send(client, line <> "\r\n")
  end

  defp random_nick do
    "machgod" <> Integer.to_string(Enum.random(0..999))
  end

  defp client_init(state, client) do
    IO.puts("Starting client init")
    nick = Map.get(state, :nick, "MachineGod")
    ident = Map.get(state, :ident, "MachGod")
    real_name = Map.get(state, :realname, "MachineGod")
    send_line(client, "NICK " <> nick)
    send_line(client, "USER #{ident} 8 * #{state[:server]} :#{real_name}")
  end

  defp client_loop(state, client, data) do
    GenServer.call(LogStore, {:raw, data})
    reply = MachineGod.IrcParser.parse_line(data)
    #IO.inspect(reply)
    case reply do
      {:welcome, _} ->
        for channel <- state[:default_channels] do
          send_line(client, "JOIN :#{channel}")
        end
        state
      {:nicknameinuse, _, _} ->
        new_nick = random_nick()
        send_line(client, "NICK " <> new_nick)
        Map.put(state, :nick, new_nick)
      {:nick, new_nick} ->
        # just for recordkeeping
        Map.put(state, :nick, new_nick)
      {:ping, cookie} ->
        send_line(client, "PONG " <> cookie)
        state
      {:topic, channel, topic} ->
        # XXX: support {:topicwhowhen, channel, who, when} properly
        # annoyingly, it's two messages together...
        GenServer.call(LogStore, {:topic, state[:server], channel, topic})
        state
      {:privmsg, from, to, message} ->
        GenServer.call(LogStore, {:privmsg, state[:server], from, to, message})
        state
      {:mode, from, to, message} ->
        GenServer.call(LogStore, {:mode, state[:server], from, to, message})
        state
      {:part, from, to, message} ->
        GenServer.call(LogStore, {:part, state[:server], from, to, message})
        state
      {:quit, from, to, message} ->
        GenServer.call(LogStore, {:quit, state[:server], from, message})
        state
      {:kick, from, to, channel, message} ->
        GenServer.call(LogStore, {:kick, state[:server], from, to, channel, message})
        state
      {:namreply, type, to, users} when false -> # disable
        # XXX: we're stripping away user rights info right now
        users_prefix = users
          |> Enum.map(&MachineGod.IrcParser.names_parse/1)
        for {_, user} <- users_prefix do
          GenServer.call(LogStore, {:join, state[:server], user, to})
        end
        state
      {:join, from, to} ->
        GenServer.call(LogStore, {:join, state[:server], from, to})
        state
      # XXX: Other types of channel message...
      _ ->
        state
    end
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, [])
  end

  @impl true
  def init(state) do
    IO.puts("Starting client sock")
    {:ok, client} = :gen_tcp.connect(state[:server], 6667, [:binary, packet: :line, active: true])
    # XXX: I guess we should be using a Map
    new_state = state 
      |> Map.new
      |> Map.put(:client, client)
    IO.puts("Starting client loop")
    client_init(new_state, client)
    {:ok, new_state}
  end

  # Intercept Erlang gen_tcp receive messages since we let the GenServer handle it
  @impl true
  def handle_info({:tcp, client, data}, state) do
    new_state = client_loop(state, client, data)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(req, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(req, from, state) do
    case req do
      {:nick, new_nick} ->
        send_line(state[:client], "NICK " <> new_nick)
      {:join, channel} ->
        send_line(state[:client], "JOIN " <> channel)
      {:part, channel} ->
        send_line(state[:client], "PART " <> channel)
      {:privmsg, target, message} ->
        send_line(state[:client], "PRIVMSG #{target} :#{message}")
      _ -> nil # nothing's really fatal here
    end
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(req, state) do
    {:noreply, state}
  end
end
