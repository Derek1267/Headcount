-- =====================================================================
-- Headcount update 2: co-captains, league invites, guest players,
-- seasons, player photos, calendar feed keys, reminder email log.
-- Run once in Supabase → SQL Editor, after schema.sql.
-- =====================================================================

-- ---------- new columns ----------
alter table public.players add column guest_game uuid references public.games(id) on delete cascade;  -- one-night fill-in
alter table public.players add column photo_v integer not null default 0;                               -- bumps when a photo changes
alter table public.games add column season text not null default 'Season 1';
alter table public.team_secrets add column cal_key text not null default substr(md5(random()::text || clock_timestamp()::text), 1, 16);

-- ---------- new tables ----------
create table public.league_invites (
  league_id  uuid primary key references public.leagues(id) on delete cascade,
  code       text not null unique
);
create table public.reminder_log (           -- written only by the reminder function (service role)
  game_id  uuid not null references public.games(id) on delete cascade,
  team_id  uuid not null references public.teams(id) on delete cascade,
  kind     text not null,
  sent_at  timestamptz not null default now(),
  primary key (game_id, team_id, kind)
);
alter table public.league_invites enable row level security;
alter table public.reminder_log  enable row level security;   -- no policies: nobody in the app can read or write it
revoke all on public.reminder_log from anon, authenticated;
create policy "league_invites: organizer reads" on public.league_invites for select to authenticated using (is_league_admin(league_id));

-- ---------- tighter rules: teams and games can only join a league you run (or via an invite) ----------
create function public.team_in_league(t uuid, l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from teams where id = t and league_id = l);
$$;
drop policy "teams: create" on public.teams;
create policy "teams: create" on public.teams for insert to authenticated
  with check (is_email_user() and created_by = auth.uid() and (league_id is null or is_league_admin(league_id)));
drop policy "games: create" on public.games;
create policy "games: create" on public.games for insert to authenticated with check (
  is_league_admin(league_id)
  or (is_captain(home_team_id) and team_in_league(home_team_id, league_id))
  or (is_captain(away_team_id) and team_in_league(away_team_id, league_id)));
drop policy "games: edit" on public.games;
create policy "games: edit" on public.games for update to authenticated
  using (is_league_admin(league_id) or is_captain(home_team_id) or is_captain(away_team_id))
  with check (is_league_admin(league_id)
    or (is_captain(home_team_id) and team_in_league(home_team_id, league_id))
    or (is_captain(away_team_id) and team_in_league(away_team_id, league_id)));

-- ---------- co-captains ----------
create function public.set_member_role(t uuid, p uuid, r text) returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  if not is_captain(t) then raise exception 'Only a captain can do this'; end if;
  if r not in ('captain','player') then raise exception 'Unknown role'; end if;
  select claimed_by into u from players where id = p and team_id = t;
  if u is null then raise exception 'That player hasn''t opened the invite link on their phone yet'; end if;
  if r = 'player' and u = auth.uid() then raise exception 'You can''t demote yourself'; end if;
  update team_members set role = r where team_id = t and user_id = u;
end $$;

-- ---------- invite other captains into your league ----------
create function public.league_invite_code(l uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not is_league_admin(l) then raise exception 'Only the league organizer can invite teams'; end if;
  select code into c from league_invites where league_id = l;
  if c is null then
    c := substr(md5(random()::text || clock_timestamp()::text || l::text), 1, 12);
    insert into league_invites (league_id, code) values (l, c);
  end if;
  return c;
end $$;
create function public.reset_league_invite(l uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not is_league_admin(l) then raise exception 'Only the league organizer can do this'; end if;
  delete from league_invites where league_id = l;
  return league_invite_code(l);
end $$;
create function public.league_preview(code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('league_id', l.id, 'name', l.name, 'sport', l.sport,
    'divisions', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name) from divisions d where d.league_id = l.id), '[]'::jsonb))
  from league_invites i join leagues l on l.id = i.league_id where i.code = league_preview.code;
$$;
create function public.join_league(code text, team_name text, div uuid, fmt text) returns uuid
language plpgsql security definer set search_path = public as $$
declare l uuid; s text; t uuid;
begin
  if not is_email_user() then raise exception 'Sign in with email to add a team'; end if;
  select i.league_id, lg.sport into l, s from league_invites i join leagues lg on lg.id = i.league_id where i.code = join_league.code;
  if l is null then raise exception 'That league invite isn''t valid anymore'; end if;
  if div is not null and not exists (select 1 from divisions where id = div and league_id = l) then raise exception 'Pick a division in this league'; end if;
  if exists (select 1 from teams where league_id = l and lower(name) = lower(team_name)) then raise exception 'A team with that name is already in this league'; end if;
  insert into teams (name, sport, format, league_id, division_id, created_by) values (team_name, s, fmt, l, div, auth.uid()) returning id into t;
  return t;
end $$;

-- ---------- player photos (Supabase Storage) ----------
create function public.set_photo(p uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  if not (is_my_player(p) or is_captain(player_team(p))) then raise exception 'You can only change your own photo'; end if;
  update players set photo_v = photo_v + 1 where id = p returning photo_v into v;
  return v;
end $$;
create function public.clear_photo(p uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_my_player(p) or is_captain(player_team(p))) then raise exception 'You can only change your own photo'; end if;
  update players set photo_v = 0 where id = p;
end $$;
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
-- path is <team id>/<player id>.jpg : captains can manage their team's photos, players their own
create policy "avatars: upload" on storage.objects for insert to authenticated with check (
  bucket_id = 'avatars' and (is_captain(((storage.foldername(name))[1])::uuid) or is_my_player((split_part(storage.filename(name), '.', 1))::uuid)));
create policy "avatars: replace" on storage.objects for update to authenticated using (
  bucket_id = 'avatars' and (is_captain(((storage.foldername(name))[1])::uuid) or is_my_player((split_part(storage.filename(name), '.', 1))::uuid)));
create policy "avatars: delete" on storage.objects for delete to authenticated using (
  bucket_id = 'avatars' and (is_captain(((storage.foldername(name))[1])::uuid) or is_my_player((split_part(storage.filename(name), '.', 1))::uuid)));

-- ---------- calendar feed key (any teammate can get the subscribe link) ----------
create function public.calendar_key(t uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when is_member(t) then (select cal_key from team_secrets where team_id = t) end;
$$;

-- ---------- who can call the new actions ----------
revoke all on function public.set_member_role(uuid,uuid,text), public.league_invite_code(uuid), public.reset_league_invite(uuid),
  public.league_preview(text), public.join_league(text,text,uuid,text), public.set_photo(uuid), public.clear_photo(uuid),
  public.calendar_key(uuid), public.team_in_league(uuid,uuid) from public, anon;
grant execute on function public.set_member_role(uuid,uuid,text), public.league_invite_code(uuid), public.reset_league_invite(uuid),
  public.league_preview(text), public.join_league(text,text,uuid,text), public.set_photo(uuid), public.clear_photo(uuid),
  public.calendar_key(uuid), public.team_in_league(uuid,uuid) to authenticated;
grant select, insert, update, delete on public.league_invites to authenticated;
alter publication supabase_realtime add table public.players;
