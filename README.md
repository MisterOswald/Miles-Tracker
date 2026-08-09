# Miles — Self-Hosted MileIQ Replacement

Personal automatic mileage tracking. A native iPhone app detects drives in the
background (MileIQ-style, near-zero battery), records the route, classifies
Business vs Personal, and syncs to a self-hosted web dashboard with CSV/PDF
reports for your CPA.

```
Miles-Tracker/
├── ios/        Native SwiftUI app (iOS 17+) — the tracker
│   ├── project.yml          XcodeGen spec (generates Miles.xcodeproj)
│   └── Miles/
│       ├── App/             Entry point, SLC background relaunch, SwiftData container
│       ├── Tracking/        Drive-detection state machine + crash recovery
│       ├── Models/          Drive, RateEntry, NamedLocation (SwiftData)
│       ├── Services/        Auto-classifier, geocoding, rate lookup
│       ├── Sync/            API client, offline-first sync engine, Keychain
│       ├── Utils/           Haversine, encoded polylines, formatters
│       └── Views/           Drive list (swipe to classify), detail map, settings
└── web/        Next.js (App Router, TypeScript) dashboard + API on Vercel
    ├── migrations/          SQL migrations + runner
    └── src/
        ├── app/api/         auth, drives CRUD, bulk sync, rates, locations, exports
        ├── app/(dashboard)/ dashboard, drive table, reports
        ├── components/map/  MapView abstraction (Leaflet/OSM default, Google optional)
        └── lib/             db, auth, polyline, CSV/PDF report builders
```

---

## How drive detection works (and why it doesn't eat your battery)

Miles never runs continuous GPS while you're not driving. The state machine:

```
        ┌──────────────────────────── idle ◀──────────────────────────┐
        │   Significant Location Changes + CLVisit + motion activity  │
        │   (all wake the app from suspended/terminated, ~0 battery)  │
        │                                                             │
        │  automotive motion / SLC while fast / visit departure       │
        ▼                                                             │
   evaluating ── no sustained movement within 3 min ──────────────────┤
        │                                                             │
        │  sustained driving speed (≥ 4.5 m/s) or high-conf automotive│
        ▼                                                             │
     active     GPS at 10 m accuracy, automotiveNavigation,           │
        │       background updates on, points < 50 m accuracy kept    │
        │                                                             │
        │  stationary/walking ≥ 3 min  OR  speed < 2 m/s ≥ 5 min      │
        ▼                                                             │
    finalize    haversine distance, reverse geocode (CLGeocoder),     │
                auto-classify, save, queue sync ──────────────────────┘
```

- **Kill recovery:** the in-progress drive is persisted to disk after every
  GPS batch. If iOS terminates the app mid-drive, the next wake (SLC fires on
  any significant movement) either resumes the drive (last point < 10 min old)
  or closes it out gracefully from persisted state.
- **Auto-classification** (in priority order): named-location rules
  (destination first, then origin) → work-hours rule (Mon–Fri window ⇒
  Business) → unclassified, awaiting a swipe.
- **Rates:** stored per-year so old drives keep their year's rate. Defaults
  seeded with IRS standard rates (2023 65.5¢ / 2024 67¢ / 2025 70¢ / 2026
  72.5¢). Heads-up: the IRS raised 2026 to 76¢ effective July 1, 2026 — the
  model is one rate per year, so set the 2026 value to whichever your CPA
  wants applied. Everything is editable in Settings → IRS Rates.

## Sync model

Offline-first. The phone works fully without a server; sync is additive.

- Local edits flag drives `needsSync` (the outbound queue). Each sync `POST
  /api/sync` pushes them and pulls everything changed since the last cursor.
- Conflicts are **last-write-wins by `updatedAt`**, and the server rejects
  stale pushes — so a reclassification made on the web dashboard wins over
  older device state (server is source of truth for web edits).
- Deletes are soft (`deletedAt`) so they propagate both ways.
- Routes travel and are stored as Google-encoded polylines (small rows; the
  Swift and TypeScript codecs are verified against Google's reference vector).

---

## iOS app setup (Xcode)

Prereqs: a Mac with Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
cd ios
xcodegen generate      # produces Miles.xcodeproj from project.yml
open Miles.xcodeproj
```

In Xcode:

1. Select the **Miles** target → *Signing & Capabilities* → pick your Team
   (a free Apple ID works). Change the bundle id if it collides
   (`com.miles.tracker` → anything unique).
2. Build & run on a **physical iPhone** (drive detection is meaningless in the
   simulator; you can simulate location, but not motion activity).

### Permissions / entitlements checklist

Everything below works on **free provisioning** — no paid-account
entitlements (no CloudKit, no push, no App Groups) are used anywhere:

- [x] App icon — `ios/Miles/Assets.xcassets/AppIcon.appiconset` (regenerate
      with `python3 tools/make_icon.py` after editing that script)
- [x] `UIBackgroundModes: location` — declared in `project.yml` (Info.plist)
- [x] `NSLocationAlwaysAndWhenInUseUsageDescription` / `NSLocationWhenInUseUsageDescription`
- [x] `NSMotionUsageDescription`
- [ ] On device: grant **Location → Always** (the app asks While-Using first,
      then upgrades — iOS shows the Always prompt after some background use;
      you can set it immediately in Settings → Miles → Location → Always)
- [ ] On device: grant **Motion & Fitness**
- [ ] On device: **Settings → General → Background App Refresh → on** for Miles

### Sideloading options

| | Free Apple ID | Paid ($99/yr) |
|---|---|---|
| Signing validity | **7 days**, then the app stops launching until re-signed | 1 year |
| Install | Xcode direct, or [AltStore](https://altstore.io)/Sideloadly — AltStore auto-refreshes the signature when your phone is on the same Wi-Fi as its companion server | Xcode, TestFlight, ad-hoc |
| App limit | 3 sideloaded apps | none meaningful |
| This app's features | all work (background location is fine on free provisioning) | all work |

Upgrading later is a **config change only**: set your paid team in
`ios/project.yml` (`DEVELOPMENT_TEAM`), regenerate, re-archive. No code
changes.

> Data survives re-signing: SwiftData storage persists across reinstalls of
> the same bundle id from the same team. If a free-account signature lapses
> for a long stretch, drives made in the gap are simply missing — another
> reason to let AltStore auto-refresh, and to sync to your own server.

---

## Web dashboard + API setup (Vercel)

Prereqs: Node 20+, a Postgres database (Vercel Postgres/Neon or Supabase),
a [Vercel](https://vercel.com) account.

### 1. Configure environment

```bash
cd web
npm install
cp .env.example .env.local
```

Fill in `.env.local`:

| Var | What |
|---|---|
| `POSTGRES_URL` | Postgres connection string. Vercel Postgres/Neon: the pooled URL. Supabase: the **Transaction pooler** URL (port 6543). |
| `AUTH_SECRET` | `openssl rand -hex 32` |
| `MILES_EMAIL` | your login email |
| `MILES_PASSWORD_HASH` | `npm run hash-password -- 'your-password'` → paste output |
| `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` | *(optional)* set only if you want Google Maps on the web; otherwise Leaflet + OpenStreetMap render with no key and no billing |

### 2. Migrate the database

```bash
npm run db:migrate        # applies web/migrations/*.sql, tracks in _migrations
```

Re-run any time; it's idempotent and only applies new files. Add future
schema changes as `web/migrations/0002_*.sql` etc.

### 3. Run locally / deploy

```bash
npm run dev               # http://localhost:3000
```

Deploy to Vercel:

```bash
npx vercel               # link the repo, set Root Directory to `web`
npx vercel env add POSTGRES_URL       # repeat for AUTH_SECRET, MILES_EMAIL,
                                      # MILES_PASSWORD_HASH (Production)
npx vercel --prod
```

(Or use the Vercel dashboard: import the GitHub repo, set **Root Directory =
`web`**, add the four env vars, deploy. If you provision Vercel Postgres from
the dashboard it injects `POSTGRES_URL` for you — still run
`npm run db:migrate` once locally against that URL.)

### 4. Connect the iPhone

On the phone: **Settings → Sync → Server & account** → enter your deployment
URL (e.g. `https://miles-yourname.vercel.app`), email, password → Sign in.
The app stores a long-lived bearer token in the Keychain and syncs
automatically after every drive, on foreground, and on demand.

---

## Web dashboard features

- **Dashboard** — yearly totals with monthly/quarterly breakdowns, business
  vs personal split, estimated deduction, unclassified count.
- **Drives** — filterable table (year/quarter/month/category), one-click
  reclassify, inline purpose notes (debounced autosave), per-drive detail
  page with the route drawn on Leaflet/OpenStreetMap (or Google Maps if you
  configured a key — the `MapView` component abstracts both).
- **Reports** — per year or quarter, CSV and printable PDF with date,
  start → end address, miles, category, purpose, rate, deduction, and totals
  — formatted for an S-Corp accountable-plan reimbursement file.

## API surface (all bearer-token or session-cookie authed)

```
POST   /api/auth/login       {email, password} → {token}  (+ session cookie)
POST   /api/auth/logout
GET    /api/drives           ?year=&month=&quarter=&category=&limit=&offset=
POST   /api/drives           create/upsert one drive
GET    /api/drives/:id
PATCH  /api/drives/:id       partial edit (bumps updated_at)
DELETE /api/drives/:id       soft delete
POST   /api/sync             {cursor, drives[]} → {serverTime, drives[]}
GET/PUT /api/rates           per-year IRS rates (PUT can back-fill drives)
GET/POST /api/locations      named auto-classify places
DELETE /api/locations/:id
GET/PUT /api/settings        key/value settings
GET    /api/export/csv       ?year=&quarter=&category=
GET    /api/export/pdf       ?year=&quarter=&category=
```

## Notes & known limits

- CLVisit and significant-location-change wakes can lag a couple of minutes
  behind the actual start of a drive; the first recorded point may be a few
  blocks from your true origin. That's inherent to low-power detection
  (MileIQ has the same behavior). Distance is computed from recorded points
  only — merge or edit a drive if GPS missed a chunk.
- Reverse geocoding is best-effort (CLGeocoder, free). Offline drives save
  with empty addresses; edit them later or let the web dashboard show
  coordinates-only drives.
- Single user by design: one email/password, one long-lived token, no
  multi-tenant anything.
