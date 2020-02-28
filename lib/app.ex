defmodule MachineGod do
  use Application

  @impl true
  def start(type, args) do
    MachineGod.Supervisor.start_link(name: MachineGod.Supervisor)
  end

end
