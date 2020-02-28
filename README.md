# MachineGod

Really dumb three-part bot:

* IRC client, connects to IRCds, scoops up logs
* SQL log manager, takes structured tuples and slams them into the database
* Simplistic web server with Plug, actually renders them with help of EEx

Uses DB2 for IBM i as a storage backend. (Yes, really.)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `machinegod` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:machinegod, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/machinegod](https://hexdocs.pm/machinegod).

