create schema irclogger;

drop table irclogger.privmsg;
drop table irclogger.log_access;

create table irclogger.log_access (
  log_access_id rowid generated always,
  server_id varchar(1024) not null,
  channel_id varchar(1024) not null,
  name varchar(1024) not null,
  slug varchar(1024) not null,
  visible numeric(1) default 1
);

-- I'm tempted to change the schema to just id, ts, raw_message;
-- but that has problems like moving the bulk of processing to the client
-- (including filtration!)
create table irclogger.privmsg (
  message_id rowid generated always,
  posted_at timestamp not null,
  server_id varchar(1024) not null,
  to varchar(1024), -- not not null because QUIT
  kicked_to varchar(1024), -- nullable because only used for KICK...
  from varchar(1024) not null, -- '%!%@%'
  action varchar(48) not null, -- PRIVMSG, JOIN, QUIT etc.
  message varchar(1024) ccsid 1208
);

insert into irclogger.log_access (server_id, channel_id, name, slug)
  values
    ('irc.freenode.net', '#lobsters', 'Lobsters', 'lobsters');

insert into irclogger.privmsg (posted_at, server_id, to, from, message, action)
  values (now(), 'irc.freenode.net', '#lobsters', 'foo!bar@xyzzy', 'Hi!', 'PRIVMSG');

select msg.posted_at, la.server_id, from, to, action, message
  from irclogger.privmsg msg
  inner join irclogger.log_access la on la.server_id = msg.server_id and la.channel_id = msg.to
  where la.slug = 'lobsters';
