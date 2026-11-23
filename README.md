# Headcount 🍻

**Who's in, who won, who's buying.**

A rec-league manager for beer-league and intramural teams. It handles availability, schedules, scores, standings, stats, lineups, and everything else a captain normally runs through a messy group chat. It's one HTML file with no app, accounts or build step.

Supports **hockey, rugby, soccer, basketball, flag football and baseball/slo-pitch**, each with its own positions, formats, standings rules and stats.

## Try it

Open `index.html` in any browser. It loads with two demo teams (a hockey team and a rugby team) so you can click around right away.

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
- Jersey colour note, rides board, beer duty rotation, chirp board, goalie/keeper/pitching rotation
- "Away for a while?" marks you out for several games at once

**Team**
- Roster with jersey numbers, positions, handedness (hockey, baseball) and subs
- **Paste a roster** straight from a group chat or spreadsheet
- Name lock: each name is tied to one phone, and switching needs captain approval
- Sub call order, dues tracker (tracking only, no payments), rugby scrum-safety certification
- Suspensions, both automatic (penalty minutes, yellow cards) and manual

**Season**
- Schedule with rainouts and postponements
- Standings per sport (hockey OTL points, rugby bonus points, soccer 3/1/0, win % for the rest)
- Season stats with separate goalie and pitching tables, MVP votes, badges and a shareable season recap card
- **League tab:** announcements, multiple divisions, top-4 playoff bracket, spirit (sportsmanship) ratings and a sub marketplace
- Season builder that draws a fair round-robin with byes, time-slot rotation and holiday skips

**Everywhere:** undo for anything destructive, a bottom tab bar on phones, and a 3-step setup for new teams.

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

1. **SQL Editor → New query**: paste `supabase/schema.sql` and run it.
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
| League games, divisions, announcements, playoffs | | | ✓ |

A captain who creates a team also becomes the organizer of its league.

### Still simulated

Reminder emails, "we're short" alerts and the calendar subscribe link show what would happen but don't send anything yet. Those need Supabase Edge Functions and a mail provider.

Free Supabase projects pause after a week with no activity. Hit **Resume project** in the dashboard if that happens.

## Tech

- One self-contained `index.html`: plain HTML, CSS and JavaScript with no framework and no build step
- [Supabase](https://supabase.com) (Postgres, auth, realtime) via `supabase-js` from a CDN
- `supabase/schema.sql`: tables, security rules and helper functions
- Fonts from Google Fonts (Bricolage Grotesque and Inter)
- Works on phones and desktops
