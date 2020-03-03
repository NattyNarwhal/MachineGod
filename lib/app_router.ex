defmodule MachineGod.AppRouter do
  use Plug.Router
  use Plug.Debugger, otp_app: :machinegod

  plug Plug.Parsers, parsers: [:urlencoded]
  plug Plug.Logger
  plug Plug.Static,
    at: "/static",
    from: {:machinegod, "priv/static"}

  plug :match
  plug :dispatch

  defp html_process(message) do
    {:safe, message_safe} = message
      |> String.trim_trailing("\x01")
      |> Phoenix.HTML.html_escape
    # XXX: Recognize URLs...
    message_safe
      |> IO.iodata_to_binary # XXX: prob slow
      |> MircParser.render
  end

  defp row_action(row) do
    case row do
      {message, "KICK", kicked_to} ->
        message_processed = html_process(message)
        "<span class=\"meta\">kicked</span> #{kicked_to} (<span class=\"message\">#{message_processed}</span>)"
      {message, "TOPIC", _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">topic set to</span> <span class=\"message\">#{message_processed}</span>"
      {message, "NOTICE", _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">announces</span> <span class=\"message\">#{message_processed}</span>"
      {"\x01ACTION" <> message, "PRIVMSG", _} ->
        message_processed = html_process(message)
        "<span class=\"message\">#{message_processed}</span>"
      {message, "PRIVMSG", _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">says</span> <span class=\"message\">#{message_processed}</span>"
      {message, "PART", _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">left the channel</span> (<span class=\"message\">#{message_processed}</span>)"
      {message, "QUIT", _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">quit the server</span> (<span class=\"message\">#{message_processed}</span>)"
      {_, "JOIN", _} ->
        "<span class=\"meta\">joined the channel</span>"
      {message, "MODE", _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">set mode to</span> <span class=\"message\">#{message_processed}</span>"
    end
  end

  defp row_to_tr(row) do
    # {{{y, m, d}, {h, m, s}}, from, to, msg, action, id, kicked_to}
    {erl_dt, to, from, message, action, id, kicked_to} = row
    {:ok, timestamp} = NaiveDateTime.from_erl(erl_dt)
    nick = from
      |> MachineGod.IrcParser.simple_name
    what = row_action({message, action, kicked_to})
    {timestamp, nick, what, id}
  end

  get "/logs" do
    slugs = GenServer.call(LogStore, :queryslugs)
      |> Enum.filter(fn slug -> elem(slug, 4) end)
    {:safe, html} = log_list_page(slugs)
    conn
    |> send_resp(200, html)
  end

  defp get_logs(conn, slug, erl_dt) do
    [slug_row] = GenServer.call(LogStore, {:queryslug, slug})
    name = elem(slug_row, 1)
    rows = GenServer.call(LogStore, {:querylogs, slug, erl_dt})
    # turning it back into a timestamp for the sake of SQL...
    {early, later} = GenServer.call(LogStore, {:querydates, slug, {erl_dt, {12, 0, 0}}})
    trs = rows
      |> Enum.map(&row_to_tr/1)
    {:safe, html} = log_page(slug, name, erl_dt, early, later, trs)
    conn
      |> send_resp(200, html)
  end

  post "/logs/:slug/" do
    [slug_row] = GenServer.call(LogStore, {:queryslug, slug})
    name = elem(slug_row, 1)
    query = conn.params["query"]
    rows = GenServer.call(LogStore, {:querysearch, slug, query}) |> IO.inspect
    trs = rows
      |> Enum.map(&row_to_tr/1)
    search_tag = Phoenix.HTML.Tag.tag(:input, [name: "query", type: :search, placeholder: "search logs...", class: "query", value: query])
    {:safe, html} = search_page(slug, name, query, search_tag, trs)
    conn
      |> send_resp(200, html)
  end

  get "/logs/:slug" do
    {erl_dt, {_, _, _}} = NaiveDateTime.local_now
      |> NaiveDateTime.to_erl
    get_logs(conn, slug, erl_dt)
  end

  get "/logs/:slug/:year/:month/:date" do
    erl_dt = {String.to_integer(year), String.to_integer(month), String.to_integer(date)}
    get_logs(conn, slug, erl_dt)
  end

  match _ do
    send_resp(conn, 404, "Sorry.")
  end

  require EEx

  EEx.function_from_file(:def, :log_page, "lib/log_page.eex", [:slug, :channel, :date, :early, :later, :rows], [ engine: Phoenix.HTML.Engine ])
  EEx.function_from_file(:def, :search_page, "lib/search_page.eex", [:slug, :channel, :query, :search_tag, :rows], [ engine: Phoenix.HTML.Engine ])
  EEx.function_from_file(:def, :log_list_page, "lib/log_list_page.eex", [:rows], [ engine: Phoenix.HTML.Engine ])
end
