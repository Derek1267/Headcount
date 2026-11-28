-- Headcount 005: small security tidy-up (from Supabase's security advisor). Run after 004.
-- helpers are only used inside security rules for signed-in users; nobody needs to call them logged-out
revoke execute on function public.is_captain(uuid), public.is_member(uuid), public.is_league_admin(uuid), public.is_my_player(uuid),
  public.player_team(uuid), public.game_team_ok(uuid,uuid) from public, anon;
grant execute on function public.is_captain(uuid), public.is_member(uuid), public.is_league_admin(uuid), public.is_my_player(uuid),
  public.player_team(uuid), public.game_team_ok(uuid,uuid) to authenticated;
-- trigger functions are never called directly
revoke execute on function public.on_league_created(), public.on_team_created() from public, anon, authenticated;
alter function public.is_email_user() set search_path = public;
