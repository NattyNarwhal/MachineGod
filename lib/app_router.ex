defmodule MachineGod.AppRouter do
  use Plug.Router
  use Plug.Debugger, otp_app: :machinegod

  plug :match
  plug :dispatch

  defp html_process(message) do
    {:safe, message_safe} = message
      |> to_string
      |> String.trim_trailing("\x01")
      |> Phoenix.HTML.html_escape
    # XXX: Recognize URLs...
    message_safe
  end

  defp row_action(row) do
    case row do
      {message, 'KICK', kicked_to} ->
        message_processed = html_process(message)
        "<span class=\"meta\">kicked</span> #{kicked_to} (<span class=\"message\">#{message_processed}</span>)"
      {message, 'TOPIC', _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">topic set to</span> <span class=\"message\">#{message_processed}</span>"
      {message, 'NOTICE', _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">announces</span> <span class=\"message\">#{message_processed}</span>"
      {'\x01ACTION' ++ message, 'PRIVMSG', _} ->
        message_processed = html_process(message)
        "<span class=\"message\">#{message_processed}</span>"
      {message, 'PRIVMSG', _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">says</span> <span class=\"message\">#{message_processed}</span>"
      {message, 'PART', _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">left the channel</span> (<span class=\"message\">#{message_processed}</span>)"
      {message, 'QUIT', _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">quit the server</span> (<span class=\"message\">#{message_processed}</span>)"
      {_, 'JOIN', _} ->
        "<span class=\"meta\">joined the channel</span>"
      {message, 'MODE', _} ->
        message_processed = html_process(message)
        "<span class=\"meta\">set mode to</span> <span class=\"message\">#{message_processed}</span>"
    end
  end

  defp row_to_tr(row) do
    # {{{y, m, d}, {h, m, s}}, from, to, msg, action, id, kicked_to}
    {erl_dt, to, from, message, action, id, kicked_to} = row
    {:ok, timestamp} = NaiveDateTime.from_erl(erl_dt)
    nick = from
      |> to_string
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
    trs = rows
      |> Enum.map(&row_to_tr/1)
    {:safe, html} = log_page(slug, name, erl_dt, trs)
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

  EEx.function_from_file(:def, :log_page, "lib/log_page.eex", [:slug, :channel, :date, :rows], [ engine: Phoenix.HTML.Engine ])
  EEx.function_from_file(:def, :log_list_page, "lib/log_list_page.eex", [:rows], [ engine: Phoenix.HTML.Engine ])
end
