<p align="center">
  <img src="logo.svg" alt="Headcount logo" width="96" height="96">
</p>

<h1 align="center">Headcount 🍻</h1>

<p align="center">
  <strong>Who's in, who won, who's buying.</strong><br>
  Hockey · Rugby · Soccer · Basketball · Flag football · Baseball/slo-pitch
</p>

<p align="center">
  <a href="https://derek1267.github.io/Headcount/"><strong>▶ Try it: derek1267.github.io/Headcount</strong></a>
</p>

---

A rec-league manager for beer-league and intramural teams. It handles availability, schedules, scores, standings, stats, lineups, and everything else a captain normally runs through a messy group chat. It's one HTML file with no app, accounts or build step.

Each sport has its own positions, formats, standings rules and stats.

## Try it

Open the [live site](https://derek1267.github.io/Headcount/), or open `index.html` in any browser. It loads with two demo teams (a hockey team and a rugby team) so you can click around right away.

| Role | How to get in | Demo PIN |
|---|---|---|
| Player | Default view. Tap your name once. | none |
| Captain | Tap **🔒 Captain** at the top | `1234` |
| League organizer | League tab, then **Organizer login** | `0000` |

Use **Reset demo** at the bottom of the page to start fresh.

## Features

**Game day**
- One-tap In / Maybe / Out, and a live headcount that warns when you're short or missing a specialist (no goalie, no front row, no catcher…)
- Coloured tally of who's in, maybe, out and hasn't replied
- **Live scoring:** tap as goals and tries happen, and the final score and stats fill themselves in
- Lineup builder (hockey lines, rugby 1–15, soccer XI, baseball field positions and batting order)
- Your own home and away jersey colours, with a clash warning against the other team's
- Guest players for one night, MVP vote open to the whole roster
- Rides board, beer duty rotation, chirp board, goalie/keeper/pitching rotation
- "Away for a while?" marks you out for several games at once

**Team**
- Roster with jersey numbers, colour-coded positions (can be switched off), handedness (hockey, baseball), subs and player photos
- Co-captains
- **Paste a roster** straight from a group chat or spreadsheet
- Name lock: each name is tied to one phone, and switching needs captain approval
- Sub call order, dues tracker (tracking only, no payments), rugby scrum-safety certification
- Suspensions, both automatic (penalty minutes, yellow cards) and manual

**Season**
- Schedule with rainouts and postponements
- **Add games by hand** one at a time, or paste the schedule your league already sent ("Nov 27 8:30 PM vs Sin Bin Sinners, Northside Arena")
- Venue info and parking tips, all-time head-to-head record against each opponent
- Standings per sport (hockey OTL points, rugby bonus points, soccer 3/1/0, win % for the rest)
- Season stats with separate goalie and pitching tables, attendance %, MVP votes, badges and shareable season and game recaps
- Multiple seasons with archived past seasons and career stats
- Export stats and the schedule as CSV; a live calendar feed for Google or Apple Calendar
- **Team pages:** every team in the league gets a page with their home rink or field, jersey colours, captain, coaches, record, last 5 results and roster (first name and last initial only). Captains choose what to share, players can hide their name, and **Message captain** emails the other team's captain without showing anyone's address
- **League tab:** announcements, divisions in name order, invite other captains with a link, top-4 playoff bracket, spirit (sportsmanship) ratings and a sub marketplace
- Season builder that draws a fair round-robin with byes, time-slot rotation and holiday skips

**Everywhere:** add it to your phone's home screen and it opens full screen like an app (with an offline fallback), light and dark mode, rows flash when a teammate changes something, undo for anything destructive, a bottom tab bar on phones, and a 3-step setup for new teams.

## Put it on GitHub Pages

1. Create a new repository (for example `headcount`) and upload `index.html`, this `README.md` and the `supabase/` folder.
2. In the repo, go to **Settings → Pages**.
3. Under **Build and deployment**, pick **Deploy from a branch**, choose `main` and `/ (root)`, then **Save**.
4. After a minute or so your site is live at `https://<your-username>.github.io/headcount/`.

The **Invite players** link uses whatever address the page is hosted at, so it'll point at your GitHub Pages URL automatically.

## Two kinds of teams

- **Demo teams** live only in your browser. Good for poking around. Nothing is shared.
- **Live teams** are saved in Supabase and shared with your whole team. Captains sign in with an email link. Players don't sign in at all: they open the invite link, tap their name once, and that name is locked to their phone.

The page connects to this Supabase project (set at the top of the cloud section in `index.html`):

```
SB_URL = https://wkyjixmlzskiygyjgoyd.supabase.co
SB_KEY = sb_publishable_…   (the public "publishable" key, safe to ship)
```

Never put the **secret** / **service_role** key in this file.

## Supabase setup (one time)

1. **SQL Editor → New query**: paste `supabase/schema.sql` and run it. Then do the same with `supabase/002_more_features.sql` (guests, photos, seasons, league invites, calendar keys), `supabase/004_team_pages.sql` (team pages) and `supabase/005_hardening.sql` (security tidy-up). Run them in that order, once each.
2. **Authentication → Sign In / Providers**: turn on **Allow anonymous sign-ins** (players) and keep **Email** on (captains).
3. **Authentication → URL Configuration**: set **Site URL** to your GitHub Pages address, e.g. `https://<your-username>.github.io/headcount/`, and add the same address under **Redirect URLs**. Sign-in links won't work without this.
4. Optional: the built-in email service only sends 2 sign-in emails an hour, and only to people in your Supabase organization. If other captains or organizers need to sign in, add custom SMTP (Authentication → Emails → SMTP Settings) using a free provider.

### Who can do what

Enforced by the database itself (Row Level Security), not just the page:

| | Player (guest) | Captain | Organizer |
|---|---|---|---|
| Set own availability, chirp, MVP vote, rides, log a beer | ✓ | ✓ | |
| Set anyone's availability | | ✓ | |
| Roster, scores, stats, lineups, team settings | | ✓ | |
| See player emails | | ✓ | |
| Approve a name moving to a new phone | | ✓ | |
| League games, divisions, announcements, playoffs, new seasons | | | ✓ |
| Send team emails (nudge, subs, dues) | | ✓ | |
| Invite other captains into the league | | | ✓ |

A captain who creates a team also becomes the organizer of its league.

### Reminder emails and the calendar feed (optional)

These use two small Supabase Edge Functions in `supabase/functions/`. Without them the rest of the app works fine, and the buttons say email isn't switched on yet.

**1. Get a free Brevo account** (300 emails a day, no credit card, no domain needed).
- Sign up at brevo.com. Under **Senders, Domains & Dedicated IPs → Senders**, add the email address the reminders should come from and click the link Brevo emails you.
- Under **SMTP & API → API Keys**, create a key. Keep it secret: it goes into Supabase, never into `index.html`.

**2. Deploy the two functions.** In Supabase: **Edge Functions → Deploy a new function → Via Editor**.
- Name one `send-reminders` and paste `supabase/functions/send-reminders/index.ts`. Deploy.
- Name the other `calendar` and paste `supabase/functions/calendar/index.ts`. Deploy.
- Open each function's **Details** and turn **off** "Verify JWT" (each function checks who's calling itself; the calendar has to work from Google Calendar, which has no login).

**3. Add the secrets.** **Edge Functions → Secrets**, add:

| Name | Value |
|---|---|
| `BREVO_API_KEY` | the Brevo API key |
| `FROM_EMAIL` | the sender address you verified in Brevo |
| `FROM_NAME` | `Headcount` (or your team name) |
| `SITE_URL` | your GitHub Pages address, e.g. `https://derek1267.github.io/Headcount/` |
| `CRON_SECRET` | any long random string you make up |

**4. Turn on automatic reminders.** Open `supabase/003_reminder_cron.sql`, replace `YOUR-CRON-SECRET` with the same `CRON_SECRET`, and run it in the SQL Editor. Every 30 minutes it emails players who haven't replied (as many hours before the game as the captain picked in Team settings), and 24 hours out it emails the subs if the team is short.

What the captain buttons do once it's on: **Nudge** emails everyone who hasn't replied, **Ping subs** emails the next sub in the call order (tap again to ask the next one), and the dues **Remind** button emails whoever hasn't paid. Only captains can send, and only to players who have an email on file.

**Bonus:** Brevo also gives you SMTP details (**SMTP & API → SMTP**). Put them in Supabase **Authentication → Emails → SMTP Settings** and sign-in links can go to anyone, not just your Supabase organization.

Free Supabase projects pause after a week with no activity. Hit **Resume project** in the dashboard if that happens.

## Tech

- One self-contained `index.html`: plain HTML, CSS and JavaScript with no framework and no build step
- [Supabase](https://supabase.com) (Postgres, auth, realtime, storage for photos) via `supabase-js` from a CDN
- `supabase/schema.sql`, `002_more_features.sql`, `003_reminder_cron.sql`, `004_team_pages.sql`, `005_hardening.sql`: tables, security rules, helper functions and the reminder schedule
- `manifest.webmanifest`, `sw.js`, `icons/`: the home-screen app icon and offline support
- `supabase/functions/`: the reminder email and calendar feed Edge Functions (Deno, Brevo for email)
- Fonts from Google Fonts (Bricolage Grotesque and Inter)
- Works on phones and desktops
