defmodule MachineGod.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(opts) do
    children = [
      MachineGod.LogStore,
      Supervisor.child_spec({MachineGod.IrcClient, [ server: 'irc.interlinked.me', default_channels: ["#bothell"] ]}, id: :irc_interlinked),
      Supervisor.child_spec({MachineGod.IrcClient, [ server: 'irc.freenode.net', default_channels: ["#machinegod", "#lobsters"] ]}, id: :irc_freenode),
      {Plug.Cowboy, scheme: :http, plug: MachineGod.AppRouter, options: [port: 1337]}
    ]
    #{:ok, _} = GenServer.start_link(MachineGod.LogStore, :ok, name: LogStore)
    #MachineGod.IrcClient.start_irc('irc.interlinked.me')
    Supervisor.init(children, strategy: :one_for_one)
  end
end
