-- =====================================================================
-- Headcount: Supabase database setup
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run on a brand-new project. Running it twice will error on
-- "already exists"; that's fine, it means it's already set up.
--
-- Who can do what (enforced by Row Level Security):
--   • Captains & league organizers sign in with email.
--   • Players use an invisible anonymous login per phone (no account).
--     Claiming a name links it to that phone, which is the real "name lock".
--   • Players set only their own availability, MVP vote, rides, chirps.
--   • Captains manage their roster, scores, stats, lineups and settings.
--   • Organizers manage league games, divisions and announcements.
--   • Player emails are visible to captains only.
-- =====================================================================

-- ---------- core tables ----------------------------------------------

create table public.leagues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  sport       text not null check (sport in ('hockey','rugby','soccer','basketball','football','baseball')),
  settings    jsonb not null default '{}'::jsonb,      -- e.g. discipline rules
  created_by  uuid not null default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table public.league_admins (
  league_id  uuid not null references public.leagues(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  primary key (league_id, user_id)
);

create table public.divisions (
  id         uuid primary key default gen_random_uuid(),
  league_id  uuid not null references public.leagues(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  unique (league_id, name)
);

create table public.teams (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid references public.leagues(id) on delete set null,
  division_id  uuid references public.divisions(id) on delete set null,
  name         text not null check (char_length(name) between 1 and 40),
  sport        text not null check (sport in ('hockey','rugby','soccer','basketball','football','baseball')),
  format       text,
  -- captain-managed team state: reminders, innings limit, dues amount + who paid,
  -- beer duty order/shift, goalie rotation, kit overrides, sub call order,
  -- manual suspensions, playoff picks
  settings     jsonb not null default '{}'::jsonb,
  created_by   uuid not null default auth.uid() references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- join codes live apart from teams so ordinary members can't read them
create table public.team_secrets (
  team_id    uuid primary key references public.teams(id) on delete cascade,
  join_code  text not null unique
);

create table public.team_members (
  team_id    uuid not null references public.teams(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'player' check (role in ('captain','player')),
  joined_at  timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table public.players (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  first_name  text not null check (char_length(first_name) between 1 and 30),
  last_name   text not null default '' check (char_length(last_name) <= 30),
  pos         text not null,
  num         smallint check (num between 0 and 99),
  hand        text,
  is_sub      boolean not null default false,
  cert        jsonb not null default '{}'::jsonb,   -- rugby: {"fr":true,"lk":false}
  claimed_by  uuid references auth.users(id) on delete set null,   -- the phone this name is locked to
  created_at  timestamptz not null default now(),
  unique (team_id, num)
);
create unique index players_one_claim_per_team on public.players (team_id, claimed_by) where claimed_by is not null;

create table public.player_private (
  player_id  uuid primary key references public.players(id) on delete cascade,
  email      text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

create table public.games (
  id            uuid primary key default gen_random_uuid(),
  league_id     uuid references public.leagues(id) on delete cascade,
  division_id   uuid references public.divisions(id) on delete set null,
  round         smallint,
  starts_at     timestamptz,                 -- null while postponed with no date
  venue         text,
  home_name     text not null,
  away_name     text not null,
  home_team_id  uuid references public.teams(id) on delete set null,   -- set when that team uses Headcount
  away_team_id  uuid references public.teams(id) on delete set null,
  status        text not null default 'scheduled' check (status in ('scheduled','final','cancelled','postponed')),
  home_score    smallint check (home_score >= 0),
  away_score    smallint check (away_score >= 0),
  home_tries    smallint check (home_tries >= 0),
  away_tries    smallint check (away_tries >= 0),
  overtime      boolean not null default false,
  moved_from    timestamptz,
  cancel_reason text,
  created_at    timestamptz not null default now(),
  check (status <> 'final' or (home_score is not null and away_score is not null))
);
create index games_league_idx on public.games (league_id, starts_at);
create index games_home_idx on public.games (home_team_id);
create index games_away_idx on public.games (away_team_id);

-- ---------- per-game team data ----------------------------------------

create table public.availability (
  game_id     uuid not null references public.games(id) on delete cascade,
  player_id   uuid not null references public.players(id) on delete cascade,
  status      text not null check (status in ('in','maybe','out')),
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now(),
  primary key (game_id, player_id)
);

create table public.stat_lines (
  game_id    uuid not null references public.games(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  kind       text not null check (kind in ('skater','keeper')),   -- keeper = goalie / goalkeeper / pitcher line
  data       jsonb not null default '{}'::jsonb,                 -- {"g":1,"a":2} etc.
  primary key (game_id, player_id, kind)
);

create table public.lineups (
  game_id  uuid not null references public.games(id) on delete cascade,
  team_id  uuid not null references public.teams(id) on delete cascade,
  data     jsonb not null default '{}'::jsonb,                   -- {"slots":[...],"order":[...]}
  primary key (game_id, team_id)
);

create table public.chirps (
  id          uuid primary key default gen_random_uuid(),
  game_id     uuid not null references public.games(id) on delete cascade,
  team_id     uuid not null references public.teams(id) on delete cascade,
  player_id   uuid references public.players(id) on delete set null,   -- null = posted as captain
  author_id   uuid not null default auth.uid(),
  body        text not null check (char_length(body) between 1 and 140),
  created_at  timestamptz not null default now()
);

create table public.mvp_votes (
  game_id    uuid not null references public.games(id) on delete cascade,
  team_id    uuid not null references public.teams(id) on delete cascade,
  voter_id   uuid not null references public.players(id) on delete cascade,
  pick_id    uuid not null references public.players(id) on delete cascade,
  primary key (game_id, voter_id),
  check (voter_id <> pick_id)
);

create table public.rides (
  id          uuid primary key default gen_random_uuid(),
  game_id     uuid not null references public.games(id) on delete cascade,
  team_id     uuid not null references public.teams(id) on delete cascade,
  driver_id   uuid not null references public.players(id) on delete cascade,
  seats       smallint not null check (seats between 1 and 8),
  leaving_from text not null check (char_length(leaving_from) between 1 and 40),
  unique (game_id, driver_id)
);

create table public.ride_riders (
  ride_id    uuid not null references public.rides(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  primary key (ride_id, player_id)
);

create table public.ride_needs (
  game_id    uuid not null references public.games(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  primary key (game_id, player_id)
);

create table public.beer_rounds (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams(id) on delete cascade,
  player_id  uuid not null references public.players(id) on delete cascade,
  logged_by  uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.claim_requests (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  player_id   uuid not null references public.players(id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (player_id, user_id)
);

create table public.spirit_ratings (
  game_id        uuid not null references public.games(id) on delete cascade,
  rater_team_id  uuid not null references public.teams(id) on delete cascade,
  rated_name     text not null,
  score          smallint not null check (score between 1 and 5),
  created_at     timestamptz not null default now(),
  primary key (game_id, rater_team_id)
);

create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  league_id   uuid not null references public.leagues(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 240),
  created_by  uuid not null default auth.uid(),
  created_at  timestamptz not null default now()
);

create table public.free_agents (
  id          uuid primary key default gen_random_uuid(),
  league_id   uuid not null references public.leagues(id) on delete cascade,
  first_name  text not null check (char_length(first_name) between 1 and 30),
  last_name   text not null default '' check (char_length(last_name) <= 30),
  pos         text not null,
  nights      text check (char_length(nights) <= 40),
  note        text check (char_length(note) <= 120),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- ---------- helper functions used by the security rules ---------------
-- security definer so the rules can look things up without recursion;
-- each one only answers yes/no about the signed-in user.

create function public.is_member(t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members where team_id = t and user_id = auth.uid());
$$;

create function public.is_captain(t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members where team_id = t and user_id = auth.uid() and role = 'captain');
$$;

create function public.is_league_admin(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from league_admins where league_id = l and user_id = auth.uid());
$$;

create function public.player_team(p uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select team_id from players where id = p;
$$;

create function public.is_my_player(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from players where id = p and claimed_by = auth.uid());
$$;

create function public.is_email_user() returns boolean
language sql stable as $$
  select auth.uid() is not null and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false;
$$;

create function public.game_team_ok(g uuid, t uuid) returns boolean   -- is team t playing in game g?
language sql stable security definer set search_path = public as $$
  select exists (select 1 from games where id = g and (home_team_id = t or away_team_id = t));
$$;

-- ---------- automatic setup when leagues / teams are created ----------

create function public.on_league_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into league_admins (league_id, user_id) values (new.id, new.created_by);
  return new;
end $$;
create trigger league_created after insert on public.leagues
  for each row execute function public.on_league_created();

create function public.on_team_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into team_members (team_id, user_id, role) values (new.id, new.created_by, 'captain');
  insert into team_secrets (team_id, join_code)
    values (new.id, substr(md5(random()::text || clock_timestamp()::text || new.id::text), 1, 10));
  return new;
end $$;
create trigger team_created after insert on public.teams
  for each row execute function public.on_team_created();

-- ---------- actions the app calls (RPCs) ------------------------------

-- Player opens the invite link: join the team as a player.
create function public.join_team(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select team_id into t from team_secrets where join_code = code;
  if t is null then raise exception 'That invite link isn''t valid anymore'; end if;
  insert into team_members (team_id, user_id, role) values (t, auth.uid(), 'player')
    on conflict (team_id, user_id) do nothing;
  return t;
end $$;

-- Player taps their name: lock it to this phone (fails if another phone has it).
create function public.claim_player(p uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid; owner uuid;
begin
  select team_id, claimed_by into t, owner from players where id = p;
  if t is null then raise exception 'Player not found'; end if;
  if not is_member(t) then raise exception 'Join the team first'; end if;
  if owner is not null and owner <> auth.uid() then raise exception 'That name is already linked to another phone'; end if;
  update players set claimed_by = null where team_id = t and claimed_by = auth.uid() and id <> p;
  update players set claimed_by = auth.uid() where id = p;
end $$;

-- "Not me?": release this phone's claim on a team.
create function public.release_player(t uuid) returns void
language sql security definer set search_path = public as $$
  update players set claimed_by = null where team_id = t and claimed_by = auth.uid();
$$;

-- Captain approves "it's me on a new phone".
create function public.approve_claim(req uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r claim_requests;
begin
  select * into r from claim_requests where id = req;
  if r.id is null then raise exception 'Request not found'; end if;
  if not is_captain(r.team_id) then raise exception 'Only a captain can approve this'; end if;
  update players set claimed_by = null where team_id = r.team_id and claimed_by = r.user_id;
  update players set claimed_by = r.user_id where id = r.player_id;
  delete from claim_requests where id = req;
end $$;

-- Captain makes a new invite link (old one stops working).
create function public.reset_join_code(t uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not is_captain(t) then raise exception 'Only a captain can do this'; end if;
  c := substr(md5(random()::text || clock_timestamp()::text), 1, 10);
  update team_secrets set join_code = c where team_id = t;
  return c;
end $$;

-- ---------- privileges ------------------------------------------------
-- Signed-in users (email or anonymous) get table access; RLS decides rows.
-- Visitors with no session get nothing.

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on function public.join_team(text), public.claim_player(uuid), public.release_player(uuid),
  public.approve_claim(uuid), public.reset_join_code(uuid) from public, anon;
grant execute on function public.join_team(text), public.claim_player(uuid), public.release_player(uuid),
  public.approve_claim(uuid), public.reset_join_code(uuid) to authenticated;

-- ---------- row level security ----------------------------------------

alter table public.leagues        enable row level security;
alter table public.league_admins  enable row level security;
alter table public.divisions      enable row level security;
alter table public.teams          enable row level security;
alter table public.team_secrets   enable row level security;
alter table public.team_members   enable row level security;
alter table public.players        enable row level security;
alter table public.player_private enable row level security;
alter table public.games          enable row level security;
alter table public.availability   enable row level security;
alter table public.stat_lines     enable row level security;
alter table public.lineups        enable row level security;
alter table public.chirps         enable row level security;
alter table public.mvp_votes      enable row level security;
alter table public.rides          enable row level security;
alter table public.ride_riders    enable row level security;
alter table public.ride_needs     enable row level security;
alter table public.beer_rounds    enable row level security;
alter table public.claim_requests enable row level security;
alter table public.spirit_ratings enable row level security;
alter table public.announcements  enable row level security;
alter table public.free_agents    enable row level security;

-- leagues: anyone signed in can see them (standings are public in a league);
-- only email users create them; only organizers edit them.
create policy "leagues: read"   on public.leagues for select to authenticated using (true);
create policy "leagues: create" on public.leagues for insert to authenticated with check (is_email_user() and created_by = auth.uid());
create policy "leagues: edit"   on public.leagues for update to authenticated using (is_league_admin(id)) with check (is_league_admin(id));
create policy "leagues: delete" on public.leagues for delete to authenticated using (is_league_admin(id));

create policy "league_admins: read"   on public.league_admins for select to authenticated using (true);
create policy "league_admins: add"    on public.league_admins for insert to authenticated with check (is_league_admin(league_id));
create policy "league_admins: remove" on public.league_admins for delete to authenticated using (is_league_admin(league_id));

create policy "divisions: read"  on public.divisions for select to authenticated using (true);
create policy "divisions: write" on public.divisions for all to authenticated using (is_league_admin(league_id)) with check (is_league_admin(league_id));

-- teams: names are visible league-wide; captains edit; email users create.
create policy "teams: read"   on public.teams for select to authenticated using (true);
create policy "teams: create" on public.teams for insert to authenticated with check (is_email_user() and created_by = auth.uid());
create policy "teams: edit"   on public.teams for update to authenticated using (is_captain(id)) with check (is_captain(id));
create policy "teams: delete" on public.teams for delete to authenticated using (is_captain(id));

create policy "team_secrets: captain reads" on public.team_secrets for select to authenticated using (is_captain(team_id));

-- members: see your own membership; captains see and manage everyone on the team.
create policy "team_members: read"   on public.team_members for select to authenticated using (user_id = auth.uid() or is_captain(team_id));
create policy "team_members: promote" on public.team_members for update to authenticated using (is_captain(team_id)) with check (is_captain(team_id));
create policy "team_members: remove" on public.team_members for delete to authenticated using (is_captain(team_id) or user_id = auth.uid());

-- players: teammates can see the roster; captains manage it (claiming goes through claim_player()).
create policy "players: read"   on public.players for select to authenticated using (is_member(team_id));
create policy "players: add"    on public.players for insert to authenticated with check (is_captain(team_id));
create policy "players: edit"   on public.players for update to authenticated using (is_captain(team_id)) with check (is_captain(team_id));
create policy "players: delete" on public.players for delete to authenticated using (is_captain(team_id));

create policy "player_private: captain only" on public.player_private for all to authenticated
  using (is_captain(player_team(player_id))) with check (is_captain(player_team(player_id)));

-- games: schedule and scores are visible league-wide; organizers manage all games,
-- captains can create games for their own team and update games they play in.
create policy "games: read"   on public.games for select to authenticated using (true);
create policy "games: create" on public.games for insert to authenticated
  with check (is_league_admin(league_id) or is_captain(home_team_id) or is_captain(away_team_id));
create policy "games: edit"   on public.games for update to authenticated
  using (is_league_admin(league_id) or is_captain(home_team_id) or is_captain(away_team_id))
  with check (is_league_admin(league_id) or is_captain(home_team_id) or is_captain(away_team_id));
create policy "games: delete" on public.games for delete to authenticated using (is_league_admin(league_id));

-- availability: teammates see it; you set your own, captains set anyone's.
create policy "availability: read"  on public.availability for select to authenticated using (is_member(player_team(player_id)));
create policy "availability: write" on public.availability for all to authenticated
  using (is_my_player(player_id) or is_captain(player_team(player_id)))
  with check (is_my_player(player_id) or is_captain(player_team(player_id)));

create policy "stat_lines: read"  on public.stat_lines for select to authenticated using (is_member(player_team(player_id)));
create policy "stat_lines: write" on public.stat_lines for all to authenticated
  using (is_captain(player_team(player_id))) with check (is_captain(player_team(player_id)));

create policy "lineups: read"  on public.lineups for select to authenticated using (is_member(team_id));
create policy "lineups: write" on public.lineups for all to authenticated using (is_captain(team_id)) with check (is_captain(team_id) and game_team_ok(game_id, team_id));

-- chirps: teammates read; post as yourself (or as captain); delete your own, captains delete any.
create policy "chirps: read"   on public.chirps for select to authenticated using (is_member(team_id));
create policy "chirps: post"   on public.chirps for insert to authenticated with check (
  author_id = auth.uid() and game_team_ok(game_id, team_id) and
  ((player_id is not null and is_my_player(player_id) and player_team(player_id) = team_id) or (player_id is null and is_captain(team_id))));
create policy "chirps: delete" on public.chirps for delete to authenticated using (author_id = auth.uid() or is_captain(team_id));

-- MVP: vote as your own player for a teammate; change or take back your vote.
create policy "mvp: read"  on public.mvp_votes for select to authenticated using (is_member(team_id));
create policy "mvp: vote"  on public.mvp_votes for all to authenticated
  using (is_my_player(voter_id))
  with check (is_my_player(voter_id) and player_team(voter_id) = team_id and player_team(pick_id) = team_id and game_team_ok(game_id, team_id));

-- rides: offer as yourself; grab or leave a seat as yourself; drivers and captains can clear.
create policy "rides: read"   on public.rides for select to authenticated using (is_member(team_id));
create policy "rides: offer"  on public.rides for insert to authenticated with check (is_my_player(driver_id) and player_team(driver_id) = team_id and game_team_ok(game_id, team_id));
create policy "rides: edit"   on public.rides for update to authenticated using (is_my_player(driver_id)) with check (is_my_player(driver_id));
create policy "rides: delete" on public.rides for delete to authenticated using (is_my_player(driver_id) or is_captain(team_id));

create policy "ride_riders: read"  on public.ride_riders for select to authenticated using (is_member(player_team(player_id)));
create policy "ride_riders: join"  on public.ride_riders for insert to authenticated with check (is_my_player(player_id));
create policy "ride_riders: leave" on public.ride_riders for delete to authenticated using (is_my_player(player_id) or is_captain(player_team(player_id)));

create policy "ride_needs: read"   on public.ride_needs for select to authenticated using (is_member(player_team(player_id)));
create policy "ride_needs: add"    on public.ride_needs for insert to authenticated with check (is_my_player(player_id));
create policy "ride_needs: remove" on public.ride_needs for delete to authenticated using (is_my_player(player_id) or is_captain(player_team(player_id)));

-- beer: log a round for yourself, captains can log for anyone and fix mistakes.
create policy "beer: read"   on public.beer_rounds for select to authenticated using (is_member(team_id));
create policy "beer: log"    on public.beer_rounds for insert to authenticated with check (
  logged_by = auth.uid() and player_team(player_id) = team_id and (is_my_player(player_id) or is_captain(team_id)));
create policy "beer: delete" on public.beer_rounds for delete to authenticated using (is_captain(team_id));

-- name requests: ask as a team member; captains see and clear them.
create policy "claims: ask"   on public.claim_requests for insert to authenticated with check (user_id = auth.uid() and is_member(team_id) and player_team(player_id) = team_id);
create policy "claims: read"  on public.claim_requests for select to authenticated using (user_id = auth.uid() or is_captain(team_id));
create policy "claims: clear" on public.claim_requests for delete to authenticated using (user_id = auth.uid() or is_captain(team_id));

-- spirit: captains rate opponents of games they played; averages are league-public.
create policy "spirit: read" on public.spirit_ratings for select to authenticated using (true);
create policy "spirit: rate" on public.spirit_ratings for all to authenticated
  using (is_captain(rater_team_id)) with check (is_captain(rater_team_id) and game_team_ok(game_id, rater_team_id));

create policy "announcements: read"  on public.announcements for select to authenticated using (true);
create policy "announcements: write" on public.announcements for all to authenticated using (is_league_admin(league_id)) with check (is_league_admin(league_id));

-- free agents: anyone signed in can list themselves; organizers can tidy up.
create policy "free_agents: read"   on public.free_agents for select to authenticated using (true);
create policy "free_agents: list"   on public.free_agents for insert to authenticated with check (user_id = auth.uid());
create policy "free_agents: edit"   on public.free_agents for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "free_agents: delete" on public.free_agents for delete to authenticated using (user_id = auth.uid() or is_league_admin(league_id));

-- ---------- realtime: live updates for the things that change on game day ----------
alter publication supabase_realtime add table public.availability, public.chirps, public.games, public.rides, public.ride_riders;
