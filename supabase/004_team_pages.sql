-- Headcount 004: team pages other teams in the league can see.
-- Run once in the SQL Editor, after schema.sql and 002_more_features.sql.

alter table public.players add column if not exists hide_public boolean not null default false;

-- signed-in user is on a team in this league, or runs it
create or replace function public.in_league(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_league_admin(l) or exists (
    select 1 from team_members m join teams t on t.id = m.team_id where t.league_id = l and m.user_id = auth.uid());
$$;

-- the public part of a team: never emails, never stats or availability.
-- Players show as first name + last initial, and only if the team shares its roster
-- and the player hasn't hidden their name.
create or replace function public.team_public(t uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tm teams; show boolean;
begin
  select * into tm from teams where id = t;
  if tm.id is null or tm.league_id is null or not in_league(tm.league_id) then raise exception 'Not in your league'; end if;
  show := coalesce((tm.settings->'profile'->>'showRoster')::boolean, true);
  return jsonb_build_object(
    'name', tm.name,
    'profile', coalesce(tm.settings->'profile', '{}'::jsonb),
    'jerseys', tm.settings->'jerseys',
    'captains', coalesce(nullif(array_remove(array[nullif(tm.settings->'profile'->>'contactName','')], null), '{}'),
      (select array_agg(p.first_name || coalesce(' ' || left(nullif(p.last_name,''),1) || '.', ''))
         from team_members m join players p on p.claimed_by = m.user_id and p.team_id = t
        where m.team_id = t and m.role = 'captain' and not p.hide_public)),
    'roster', case when show then coalesce((select jsonb_agg(jsonb_build_object(
        'first', p.first_name, 'last', coalesce(left(nullif(p.last_name,''),1) || '.', ''), 'pos', p.pos, 'num', p.num, 'sub', p.is_sub)
        order by p.is_sub, p.pos, p.first_name)
      from players p where p.team_id = t and not p.hide_public and p.guest_game is null), '[]'::jsonb) end,
    'hidden', (select count(*) from players p where p.team_id = t and p.hide_public and p.guest_game is null));
end $$;

-- a player can hide their own name (captains can do it from the roster)
create or replace function public.set_hide_public(p uuid, v boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (is_my_player(p) or is_captain(player_team(p))) then raise exception 'You can only change your own name setting'; end if;
  update players set hide_public = v where id = p;
end $$;

-- "Message captain" emails, kept to stop spam (only the email function can read it)
create table if not exists public.contact_log (
  sender uuid not null, to_team uuid not null references teams(id) on delete cascade, at timestamptz not null default now());
alter table public.contact_log enable row level security;

revoke all on function public.in_league(uuid), public.team_public(uuid), public.set_hide_public(uuid,boolean) from public, anon;
grant execute on function public.in_league(uuid), public.team_public(uuid), public.set_hide_public(uuid,boolean) to authenticated;
