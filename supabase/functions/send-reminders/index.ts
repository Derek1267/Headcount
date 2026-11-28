// Headcount: reminder emails through Brevo (free plan: 300 emails a day).
//
// Two ways in:
//   1. The every-30-minutes cron job (003_reminder_cron.sql) calls it with the
//      header  x-cron-secret: <CRON_SECRET>. It emails no-replies before each game
//      and, 24 hours out, emails subs if a team is short.
//   2. A captain taps a button in the page. The page sends the captain's login,
//      and this function checks they really are a captain of that team.
//        { mode:'nudge', team_id, game_id }      email everyone who hasn't replied
//        { mode:'subs',  team_id, game_id, positions? }  email the next sub in the call order
//        { mode:'dues',  team_id }               email everyone who hasn't paid
//        { mode:'contact', team_id, to_team, message }  email another team's captains (from a team page)
//
// Secrets (Edge Functions > Secrets): BREVO_API_KEY, FROM_EMAIL, FROM_NAME, SITE_URL, CRON_SECRET.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
import { createClient } from 'npm:@supabase/supabase-js@2';

const env = (k: string) => Deno.env.get(k) ?? '';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } });

// players needed on the field (plus a goalie for hockey) when the format doesn't say
const FIELD: Record<string, number> = { hockey: 5, rugby: 15, soccer: 11, basketball: 5, football: 7, baseball: 9 };
function needFor(team: any): number {
  const m = /(\d+)/.exec(team.format ?? '');
  return (m ? Number(m[1]) : FIELD[team.sport] ?? 6) + (team.sport === 'hockey' ? 1 : 0);
}

const esc = (s: string) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));
function when(g: any, tz: string) {
  if (!g.starts_at) return 'date to be confirmed';
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: tz || 'UTC', weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(g.starts_at));
  } catch { return new Date(g.starts_at).toUTCString(); }
}
function vsLine(team: any, g: any) {
  const home = g.home_team_id === team.id || (!g.home_team_id && g.home_name === team.name);
  return home ? `vs ${g.away_name}` : `@ ${g.home_name}`;
}

async function send(to: { email: string; name: string }[], subject: string, html: string, replyTo?: { email: string; name?: string }) {
  if (!to.length) return 0;
  if (!env('BREVO_API_KEY')) throw new Error('BREVO_API_KEY is not set');
  let sent = 0;
  // one email per person so nobody sees anyone else's address
  for (const r of to) {
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': env('BREVO_API_KEY'), 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ sender: { email: env('FROM_EMAIL'), name: env('FROM_NAME') || 'Headcount' }, to: [r], subject, htmlContent: html, ...(replyTo ? { replyTo } : {}) }),
    });
    if (res.ok) sent++; else console.error('brevo', res.status, await res.text());
  }
  return sent;
}
const wrap = (team: any, body: string, foot = 'You get this because your captain added your email to the team.') => `<div style="font-family:system-ui,sans-serif;font-size:15px;line-height:1.5;color:#221a3a">
  <p style="font-weight:800;color:#7a4bd9;margin:0 0 12px">Headcount · ${esc(team.name)}</p>${body}
  <p><a href="${esc(env('SITE_URL'))}" style="display:inline-block;background:#7a4bd9;color:#fff;padding:10px 16px;border-radius:10px;text-decoration:none;font-weight:700">Open Headcount</a></p>
  <p style="font-size:12px;color:#888">${foot}</p></div>`;

async function teamBundle(teamId: string, gameId?: string) {
  const { data: team } = await admin.from('teams').select('*').eq('id', teamId).single();
  if (!team) throw Object.assign(new Error('Team not found'), { status: 404 });
  const { data: players } = await admin.from('players').select('id,first_name,last_name,is_sub,pos').eq('team_id', teamId);
  const ids = (players ?? []).map((p: any) => p.id);
  const { data: priv } = ids.length ? await admin.from('player_private').select('player_id,email').in('player_id', ids) : { data: [] };
  const email = new Map((priv ?? []).filter((x: any) => x.email).map((x: any) => [x.player_id, x.email]));
  let game: any = null, avail = new Map<string, string>();
  if (gameId) {
    const { data: g } = await admin.from('games').select('*').eq('id', gameId).single();
    if (!g || (g.home_team_id !== teamId && g.away_team_id !== teamId)) throw Object.assign(new Error('That game isn’t this team’s'), { status: 400 });
    game = g;
    const { data: a } = await admin.from('availability').select('player_id,status').eq('game_id', gameId);
    avail = new Map((a ?? []).map((x: any) => [x.player_id, x.status]));
  }
  return { team, players: (players ?? []) as any[], email, game, avail };
}
const rcpt = (b: any, list: any[]) => list.filter((p) => b.email.has(p.id)).map((p) => ({ email: b.email.get(p.id), name: `${p.first_name} ${p.last_name}`.trim() }));

async function logged(gameId: string, teamId: string, kind: string) {
  const { data } = await admin.from('reminder_log').select('kind').eq('game_id', gameId).eq('team_id', teamId).eq('kind', kind).maybeSingle();
  return !!data;
}
const log = (gameId: string, teamId: string, kind: string) => admin.from('reminder_log').upsert({ game_id: gameId, team_id: teamId, kind });

// ---------- the actions ----------
async function nudge(b: any) {
  const todo = b.players.filter((p: any) => !p.is_sub && !b.avail.has(p.id));
  const to = rcpt(b, todo), tz = b.team.settings?.tz;
  const sent = await send(to, `Are you in? ${vsLine(b.team, b.game)}, ${when(b.game, tz)}`,
    wrap(b.team, `<p>${esc(vsLine(b.team, b.game))}<br><b>${esc(when(b.game, tz))}</b>${b.game.venue ? `<br>${esc(b.game.venue)}` : ''}</p><p>You haven’t said if you’re coming. Tap below and hit <b>In</b>, <b>Maybe</b> or <b>Out</b>.</p>`));
  return { sent, noEmail: todo.length - to.length };
}
async function shortEmail(b: any) {
  const ins = [...b.avail.values()].filter((s) => s === 'in').length, need = needFor(b.team);
  if (ins >= need) return { sent: 0, short: 0 };
  const subs = b.players.filter((p: any) => p.is_sub && !b.avail.has(p.id)), tz = b.team.settings?.tz;
  const sent = await send(rcpt(b, subs), `Can you sub? ${b.team.name} is short ${need - ins}`,
    wrap(b.team, `<p>${esc(b.team.name)} has ${ins} of ${need} for ${esc(vsLine(b.team, b.game))}, <b>${esc(when(b.game, tz))}</b>${b.game.venue ? ` at ${esc(b.game.venue)}` : ''}.</p><p>Can you fill in? Tap below and say <b>In</b>.</p>`));
  return { sent, short: need - ins };
}
async function nextSub(b: any, positions: string[] | null) {
  const order: string[] = b.team.settings?.subOrder ?? [];
  const subs = b.players.filter((p: any) => p.is_sub && b.email.has(p.id) && !b.avail.has(p.id) && (!positions || positions.includes(p.pos)))
    .sort((x: any, y: any) => ((order.indexOf(x.id) + 1) || 999) - ((order.indexOf(y.id) + 1) || 999));
  for (const p of subs) {
    if (await logged(b.game.id, b.team.id, `sub:${p.id}`)) continue;
    const tz = b.team.settings?.tz;
    const sent = await send(rcpt(b, [p]), `Can you sub? ${vsLine(b.team, b.game)}, ${when(b.game, tz)}`,
      wrap(b.team, `<p>Hi ${esc(p.first_name)}, ${esc(b.team.name)} needs a sub for ${esc(vsLine(b.team, b.game))}, <b>${esc(when(b.game, tz))}</b>${b.game.venue ? ` at ${esc(b.game.venue)}` : ''}.</p><p>Tap below and say <b>In</b> if you can make it.</p>`));
    if (sent) { await log(b.game.id, b.team.id, `sub:${p.id}`); return { sent, name: `${p.first_name} ${p.last_name}`.trim() }; }
  }
  return { sent: 0 };
}
async function dues(b: any) {
  const d = b.team.settings?.dues ?? {}, paid = d.paid ?? {};
  const todo = b.players.filter((p: any) => !p.is_sub && !paid[p.id]);
  const to = rcpt(b, todo);
  const sent = await send(to, `${b.team.name}: dues reminder`,
    wrap(b.team, `<p>Friendly reminder: team dues${d.amount ? ` are <b>$${esc(String(d.amount))}</b>` : ' are due'}. Sort it out with your captain when you can. 🍺</p>`));
  return { sent, noEmail: todo.length - to.length };
}

// ---------- a captain messages another team's captains from their team page ----------
async function contact(fromTeamId: string, user: any, body: any) {
  const msg = String(body.message ?? '').trim().slice(0, 1000);
  if (msg.length < 5) throw Object.assign(new Error('Write a little more first.'), { status: 400 });
  if (!user.email) throw Object.assign(new Error('Sign in with email to message other teams.'), { status: 403 });
  const { data: from } = await admin.from('teams').select('id,name,league_id').eq('id', fromTeamId).single();
  const { data: to } = await admin.from('teams').select('id,name,league_id,settings').eq('id', body.to_team).single();
  if (!from || !to || !from.league_id || from.league_id !== to.league_id || from.id === to.id)
    throw Object.assign(new Error('You can only message teams in your league.'), { status: 403 });
  if (to.settings?.profile?.contact === false) throw Object.assign(new Error('That team has turned off messages.'), { status: 403 });
  const day = new Date(Date.now() - 864e5).toISOString(), hour = new Date(Date.now() - 36e5).toISOString();
  const { data: recent } = await admin.from('contact_log').select('to_team,at').eq('sender', user.id).gt('at', day);
  if ((recent ?? []).length >= 5) throw Object.assign(new Error('That’s 5 messages today. Try again tomorrow.'), { status: 429 });
  if ((recent ?? []).some((r: any) => r.to_team === to.id && Date.parse(r.at) > Date.parse(hour))) throw Object.assign(new Error('You just messaged them. Give it an hour.'), { status: 429 });
  const { data: caps } = await admin.from('team_members').select('user_id').eq('team_id', to.id).eq('role', 'captain');
  const rcpts: { email: string; name: string }[] = [];
  for (const c of caps ?? []) { const { data } = await admin.auth.admin.getUserById(c.user_id); if (data?.user?.email) rcpts.push({ email: data.user.email, name: `${to.name} captain` }); }
  if (!rcpts.length) throw Object.assign(new Error('Their captain hasn’t set up email yet.'), { status: 404 });
  await admin.from('contact_log').insert({ sender: user.id, to_team: to.id });
  const sent = await send(rcpts, `Message from ${from.name}`, wrap(to,
    `<p>The captain of <b>${esc(from.name)}</b> sent you a message through Headcount:</p>
     <blockquote style="margin:0 0 12px;padding:10px 14px;border-left:3px solid #7a4bd9;background:#f6f2ff;white-space:pre-wrap">${esc(msg)}</blockquote>
     <p>Just hit reply to answer them.</p>`, 'You get this because you captain a team in this league. Turn messages off in Team settings.'), { email: user.email, name: `${from.name} captain` });
  return { sent };
}

// ---------- cron: every game in the next 3 days ----------
async function cron() {
  const now = Date.now(), soon = new Date(now + 72 * 3600e3).toISOString();
  const { data: games } = await admin.from('games').select('*').eq('status', 'scheduled').gt('starts_at', new Date(now).toISOString()).lt('starts_at', soon);
  let sent = 0;
  for (const g of games ?? []) {
    for (const teamId of [g.home_team_id, g.away_team_id].filter(Boolean)) {
      const b = await teamBundle(teamId, g.id);
      const rem = b.team.settings?.rem ?? { hours: 48, short: true }, hoursLeft = (Date.parse(g.starts_at) - now) / 3600e3;
      if (rem.hours > 0 && hoursLeft <= rem.hours && !(await logged(g.id, teamId, 'reminder'))) {
        await log(g.id, teamId, 'reminder'); sent += (await nudge(b)).sent;
      }
      if (rem.short && hoursLeft <= 24 && !(await logged(g.id, teamId, 'short'))) {
        await log(g.id, teamId, 'short'); sent += (await shortEmail(b)).sent;
      }
    }
  }
  return { games: games?.length ?? 0, sent };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
  try {
    const cronSecret = req.headers.get('x-cron-secret');
    if (cronSecret) {
      if (!env('CRON_SECRET') || cronSecret !== env('CRON_SECRET')) return json({ error: 'Bad cron secret' }, 401);
      return json(await cron());
    }
    // a captain pressing a button
    const auth = req.headers.get('Authorization') ?? '';
    const userClient = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: 'Sign in first' }, 401);
    const body = await req.json().catch(() => ({}));
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuid.test(body.team_id ?? '') || (body.game_id && !uuid.test(body.game_id))) return json({ error: 'Bad request' }, 400);
    const { data: m } = await admin.from('team_members').select('role').eq('team_id', body.team_id).eq('user_id', user.id).maybeSingle();
    if (m?.role !== 'captain') return json({ error: 'Only a captain can send team emails' }, 403);
    if (body.mode === 'contact') { if (!uuid.test(body.to_team ?? '')) return json({ error: 'Bad request' }, 400); return json(await contact(body.team_id, user, body)); }
    if (body.mode === 'dues') return json(await dues(await teamBundle(body.team_id)));
    if (!body.game_id) return json({ error: 'Which game?' }, 400);
    const b = await teamBundle(body.team_id, body.game_id);
    if (body.mode === 'nudge') return json(await nudge(b));
    if (body.mode === 'subs') return json(await nextSub(b, Array.isArray(body.positions) ? body.positions.map(String) : null));
    return json({ error: 'Unknown mode' }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message }, (e as any).status ?? 500);
  }
});
