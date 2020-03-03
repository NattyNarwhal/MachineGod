defmodule MachineGod.LogStore do
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: LogStore)
  end

  @impl true
  def init(state) do
    :ok = :odbc.start()
    {:ok, dbcon} = :odbc.connect(Application.get_env(:machinegod, :connection_string), [binary_strings: :on])
    {:ok, [ dbcon: dbcon ]}
  end

  defp fix_param(param) do
    param
  end

  defp insert_message(dbcon, server, action, from, to, message) do
    insert_message(dbcon, server, action, from, to, message, "")
  end

  defp insert_message(dbcon, server, action, from, to, message, kicked_to) do
    sql = 'insert into irclogger.privmsg'
      ++ ' (posted_at, server_id, action, to, from, message, kicked_to)'
      ++ ' values (now(), ?, ?, ?, ?, ?, ?)'
    {:updated, 1} = :odbc.param_query(dbcon, sql,
      [
        {{:sql_varchar, 1024}, [server |> to_string]},
        {{:sql_varchar, 32}, [fix_param(action)]},
        {{:sql_varchar, 1024}, [fix_param(to)]},
        {{:sql_varchar, 1024}, [fix_param(from)]},
        {{:sql_varchar, 1024}, [fix_param(message)]},
        {{:sql_varchar, 1024}, [fix_param(kicked_to)]}
      ])
    :ok
  end

  defp channel_dates(dbcon, slug, then) do
    # XXX: Turn this nasty double query into a subquery stored procedure
    # The casts are necessary or the driver will barf at us.
    # The +1day on later is necessary or times from the same day will crease it.
    # We get the timestamp instead of just date because Erlang ODBC will cast it to a string then.
    sql_early = 'select max(posted_at) as "Earlier" from irclogger.privmsg msg'
      ++ ' inner join irclogger.log_access la'
      ++ ' on la.server_id = msg.server_id and la.channel_id = msg.to'
      ++ ' where posted_at < date(cast(? as timestamp))'
      ++ ' and la.slug = ?'
    sql_later = 'select min(posted_at) as "Later" from irclogger.privmsg msg'
      ++ ' inner join irclogger.log_access la'
      ++ ' on la.server_id = msg.server_id and la.channel_id = msg.to'
      ++ ' where posted_at >= (date(cast(? as timestamp)) + 1 day)'
      ++ ' and la.slug = ?'
    {:selected, _, early_rows} = :odbc.param_query(dbcon, sql_early,
      [
        {:sql_timestamp, [then]},
        {{:sql_varchar, 1024}, [fix_param(slug)]},
      ])
    {:selected, _, later_rows} = :odbc.param_query(dbcon, sql_later,
      [
        {:sql_timestamp, [then]},
        {{:sql_varchar, 1024}, [fix_param(slug)]},
      ])
    early = case early_rows do
      [{:null}] -> nil
      [{dt}] -> dt
    end
    later = case later_rows do
      [{:null}] -> nil
      [{dt}] -> dt
    end
    {early, later}
  end

  defp search(dbcon, slug, query) do
    # XXX: Do we have FTS on db2i?
    sql = 'select msg.posted_at, msg.to, msg.from, msg.message, msg.action, msg.message_id, msg.kicked_to'
      ++ ' from irclogger.privmsg msg'
      ++ ' inner join irclogger.log_access la on msg.to = la.channel_id and msg.server_id = la.server_id'
      ++ ' where la.slug = ? and message like concat(\'%\', concat(?, \'%\')) and action = \'PRIVMSG\''
    {:selected, _, rows} = :odbc.param_query(dbcon, sql,
      [
        {{:sql_varchar, 1024}, [fix_param(slug)]},
        {{:sql_varchar, 1024}, [fix_param(query)]},
      ])
    rows
  end

  @impl true
  def handle_call(req, from, state) do
    dbcon = state[:dbcon]
    case req do
      :queryslugs ->
        sql = 'select la.slug, la.name, la.server_id, la.channel_id, la.visible'
          ++ ' from irclogger.log_access la'
          # XXX: make optional?
          ++ ' where la.visible = 1'
        {:selected, columns, rows} = :odbc.sql_query(dbcon, sql)
        {:reply, rows, state}
      {:querydates, slug, then} ->
        dates = channel_dates(dbcon, slug, then)
        {:reply, dates, state}
      {:queryslug, slug} ->
        sql = 'select la.slug, la.name, la.server_id, la.channel_id, la.visible'
          ++ ' from irclogger.log_access la'
          ++ ' where la.slug = ?'
        {:selected, columns, rows} = :odbc.param_query(dbcon, sql,
          [
            {{:sql_varchar, 1024}, [fix_param(slug)]},
          ])
        {:reply, rows, state}
      {:querylogs, slug, erl_dt} ->
        # XXX: :sql_date doesn't work for nonstrings, and sql_timestamp seems broken. ugh.
        {year, month, day} = erl_dt;
        sql = 'select msg.posted_at, msg.to, msg.from, msg.message, msg.action, msg.message_id, msg.kicked_to'
          ++ ' from irclogger.privmsg msg'
          ++ ' inner join irclogger.log_access la'
          ++ ' on la.server_id = msg.server_id and la.channel_id = msg.to'
          ++ ' where la.slug = ?'
          ++ ' and year(msg.posted_at) = ?'
          ++ ' and month(msg.posted_at) = ?'
          ++ ' and day(msg.posted_at) = ?'
        {:selected, columns, rows} = :odbc.param_query(dbcon, sql,
          [
            {{:sql_varchar, 1024}, [fix_param(slug)]},
            {:sql_integer, [year]},
            {:sql_integer, [month]},
            {:sql_integer, [day]}
          ])
        {:reply, rows, state}
      {:querysearch, slug, query} ->
        rows = search(dbcon, slug, query)
        {:reply, rows, state}
      # Don't log private messages (XXX: Handle local channels)
      {:privmsg, server, from, to, message} ->
        insert_message(dbcon, server, "PRIVMSG", from, to, message)
        #IO.puts("<#{from}> #{message}")
        {:reply, :ok, state}
      {:topic, server, from, to, message} ->
        insert_message(dbcon, server, "TOPIC", from, to, message)
        {:reply, :ok, state}
      {:topic, server, to, message} -> # XXX: see client
        insert_message(dbcon, server, "TOPIC", "", to, message)
        {:reply, :ok, state}
      {:kick, server, from, kicked_to, to, message} ->
        insert_message(dbcon, server, "KICK", from, to, message, kicked_to)
        {:reply, :ok, state}
      {:mode, server, from, to, message} ->
        insert_message(dbcon, server, "MODE", from, to, message)
        {:reply, :ok, state}
      {:part, server, from, to, message} ->
        insert_message(dbcon, server, "PART", from, to, message)
        {:reply, :ok, state}
      {:quit, server, from, message} ->
        insert_message(dbcon, server, "QUIT", from, "", message)
        {:reply, :ok, state}
      {:join, server, from, to} ->
        insert_message(dbcon, server, "JOIN", from, to, "")
        {:reply, :ok, state}
      {:raw, msg} ->
        IO.write(msg)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast(req, state) do
    {:noreply, state}
  end
end
