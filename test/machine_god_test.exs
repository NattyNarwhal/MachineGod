defmodule MachineGodTest do
  use ExUnit.Case
  doctest MachineGod

  test "greets the world" do
    assert MachineGod.hello() == :world
  end
end
