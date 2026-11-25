// Headcount: a live calendar feed for one team.
//   GET /functions/v1/calendar?team=<team id>&key=<calendar key>
// The key comes from the calendar_key() function (only team members can read it),
// so the feed URL works in Google Calendar / Apple Calendar without a login.
import { createClient } from 'npm:@supabase/supabase-js@2';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const icsText = (s: string) => String(s ?? '').replace(/\\/g, '\\\\').replace(/;/g, '\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
const stamp = (d: Date) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const fold = (line: string) => line.length <= 74 ? line : line.match(/.{1,73}/g)!.join('\r\n ');

Deno.serve(async (req) => {
  const u = new URL(req.url), team = u.searchParams.get('team') ?? '', key = u.searchParams.get('key') ?? '';
  if (!uuid.test(team) || !/^[0-9a-f]{8,64}$/i.test(key)) return new Response('Not found', { status: 404 });
  const { data: sec } = await admin.from('team_secrets').select('cal_key').eq('team_id', team).maybeSingle();
  if (!sec || sec.cal_key !== key) return new Response('Not found', { status: 404 });
  const { data: t } = await admin.from('teams').select('id,name,sport,settings').eq('id', team).single();
  const { data: games } = await admin.from('games').select('*').or(`home_team_id.eq.${team},away_team_id.eq.${team}`).not('starts_at', 'is', null);
  const len = (t?.sport === 'baseball' ? 150 : t?.sport === 'rugby' ? 100 : 75) * 60e3, now = stamp(new Date());
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Headcount//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    `X-WR-CALNAME:${icsText(t?.name ?? 'Headcount')}`, 'REFRESH-INTERVAL;VALUE=DURATION:PT1H', 'X-PUBLISHED-TTL:PT1H'];
  for (const g of games ?? []) {
    const home = g.home_team_id === team, opp = home ? g.away_name : g.home_name, start = new Date(g.starts_at);
    let summary = `${home ? 'vs' : '@'} ${opp}`;
    if (g.status === 'final') { const us = home ? g.home_score : g.away_score, them = home ? g.away_score : g.home_score; summary = `${us > them ? 'W' : us < them ? 'L' : 'D'} ${us}–${them} ${summary}`; }
    if (g.status === 'cancelled') summary = `CANCELLED: ${summary}`;
    lines.push('BEGIN:VEVENT', `UID:${g.id}@headcount`, `DTSTAMP:${now}`, `DTSTART:${stamp(start)}`, `DTEND:${stamp(new Date(+start + len))}`,
      fold(`SUMMARY:${icsText(summary)}`), ...(g.venue ? [fold(`LOCATION:${icsText(g.venue)}`)] : []),
      `STATUS:${g.status === 'cancelled' ? 'CANCELLED' : 'CONFIRMED'}`, 'END:VEVENT');
  }
  lines.push('END:VCALENDAR');
  return new Response(lines.join('\r\n') + '\r\n', { headers: { 'Content-Type': 'text/calendar; charset=utf-8', 'Cache-Control': 'max-age=900' } });
});
