# BlaBlaCase

An Android app for French travellers making day trips to **Pas de la Case (Andorra)**. It shows
how much alcohol, tobacco and other goods each traveller can legally bring back into France, and
totals that allowance for everyone in the car. It pairs this with carpooling: people sharing a car
can see who plans to bring back what, and arrange between themselves who carries what within each
person's allowance.

Every trip has the same shape: **your city → Pas de la Case → your city**, on the same day.

> **Status: unfinished, on hiatus.** Authentication, the API, the customs scraper and the
> calculator work. Carpooling and allowance sharing were built in part, but **the
> allowance-sharing code was never pushed to this repository**. See
> [Code that isn't in this repository](#code-that-isnt-in-this-repository).

> The app's interface is in French. The allowance figures are for information only; each traveller
> is responsible for their own customs compliance (the app says so on every relevant screen).

> **Disclaimer:** BlaBlaCase is not designed to help anyone get around customs law. Its purpose is
> to help people coordinate shared trips using up-to-date legal allowance figures. How users act
> on that information, and what they choose to bring across the border, is entirely their own
> responsibility and not BlaBlaCase's.

## Code that isn't in this repository

The last commit in this repository is `eabfa44` (20 April 2026, tagged `v0.4`). Allowance
sharing was developed on 20–21 April 2026, after that commit, and was **never committed or
pushed**. Every branch, tag (`v0.0`–`v0.4`), stash, reflog entry and dangling object was
searched, as well as the GitHub remote (only `main`, no pull requests, no forks). This clone of
the repository was made on 18 May 2026, so it never contained that work.

**API: deployed, source missing.** The production API at `https://api.blablacase.org` runs a
newer version than this repository. Its public OpenAPI schema (`/openapi.json`) has 25
operations, while this repository has 20. The differences:

| In production only | What it does |
|---|---|
| `PUT /trips/{id}/declarations/bulk` | Saves a member's whole "cargo" (what they plan to bring back) in one call. It replaces the single-item `PUT /trips/{id}/declarations` from this repository, which production no longer serves. |
| `GET /trips/{id}/declarations` (changed) | Now also returns each member's `display_name`. |
| `POST /trips/{id}/trade-requests` | Asks a specific trip member to carry part of your share. The request has a recipient, a message and a list of items with quantities. |
| `GET /trips/{id}/trade-requests` | Lists a trip's trade requests. |
| `GET /trade-requests/pending` | Lists the trade requests waiting for your answer. |
| `PATCH /trade-requests/{id}` | Accepts or declines a trade request. |
| `GET /trips/{id}/trade-requests/accepted` | Lists accepted trades, so every member can see who carries what for whom (described in the schema as "cargo manifest annotation"). |
| `age_group` on users | Each user's age bracket (adult / 15–17 / under 15), which can be read and updated through `/users`. |

The source for this version presumably lives on the Raspberry Pi that runs the API, since
production is built from the files there. It needs to be copied back and committed.

**Mobile app: built and tested on devices, source not found.** According to the author's
development notes from 20–21 April, the app gained:
- a "participants" / planning screen for each trip, reached from the chat's ⋮ menu or by
  long-pressing a conversation;
- +/− selectors to declare your cargo, plus a reminder above the chat input if you haven't
  declared anything yet;
- trade requests to any other member, with a message and quantities. The app warns you if
  that person already plans to bring the item. Requests can be accepted or declined both in the
  notification area and in the chat;
- carried items shown per person, with the part carried for someone else shown in amber (for
  example "1 L" plus "0.5 L for X");
- per-person warnings when someone goes over a limit, and a group check (✓ or ✗) of the car's
  totals against the allowances, with a link to the calculator;
- an age-bracket choice on the profile and at sign-up.

The source for these screens isn't in this repository, on GitHub, or on this machine. The
original working copy no longer exists. The last notes (21 April) report a bug that was still
open: an account ended up shown as carrying 3 L after declaring an extra 0.5 L.

## Current state (of the code in this repository)

### What exists and works

- **Phone authentication.** Firebase sign-in with an SMS verification code (French numbers are
  normalised to `+33`), then a display-name setup on first launch. Every API request carries a
  Firebase ID token, which the server verifies.
- **Python API and its tooling.** A FastAPI service with async SQLAlchemy on PostgreSQL,
  20 endpoints (25 in production; see above), and Docker Compose with separate `api` and
  `scheduler` containers. `.env.example` lists the variables to set.
- **DGDDI scraper.** It reads the French customs page for Andorra
  (*"Passer la douane en Andorre : taxes et franchises"*) once at startup and then every night,
  and stores 14 allowance categories. The live data was last refreshed at 00:00 UTC on
  2026-11-13.
- **Allowance calculator with group totals.** You set the number of adults, minors (15–17) and
  children (< 15). The app shows each person's allowance and the total for the group across all
  14 categories (spirits, drinks ≤ 22°, still wine, cigarettes, cigarillos, cigars, rolling
  tobacco, perfume, eau de toilette, coffee, coffee extracts, tea, tea extracts, food value),
  with a link to the official source.
- **Carpool board: posting trips and requesting seats.** Drivers post a round trip: departure
  city (autocompleted via OpenStreetMap Nominatim, France only), date, departure and return
  times, 1–8 seats, and notes. Other users browse open trips (their own trips appear first) and
  ask for a seat with an optional message. The driver accepts or rejects each request, and the
  seat count and `open`/`full` status update automatically.

### What is incomplete

- **Carpooling**, by the author's estimate about two weeks of work away from being usable:
  - A group chat for each trip, for the driver and accepted passengers. It posts an automatic
    welcome message when someone is accepted and only shows the last 72 hours. It updates by
    polling every 5 seconds, and nothing deletes old messages from the database.
  - An inbox with unread indicators and pending requests. Unread, mute and hide state is only
    stored on the phone, and "mute" does nothing yet because there are no notifications.
  - "My trips" (split into trips you drive and trips you ride in) and public profiles showing
    ratings.
  - A trip's lifecycle stops at `open`/`full`. Trips never become `completed`, and the app has
    no button to cancel one, although the API supports it (`DELETE /trips/{id}`).
  - Ratings have an API endpoint (1–5 stars, from departure until 7 days after) but no screen to
    submit them.
- **Allowance sharing.** In this repository there is only the first version of the
  declarations API (`GET` and single-item `PUT /trips/{id}/declarations`). The app never calls
  it. The more complete version described above is deployed but not committed.
- **Website (`website/`).** A static landing page with a browser version of the calculator. It
  doesn't currently load any data because it points at the wrong API domain (see
  [Goals](#goals)).

### What is missing

- Push notifications (`firebase_messaging` is a dependency but unused).
- Profile photos (the button shows a "coming soon" dialog).
- Everything needed for a release: the app isn't on Google Play, AdMob uses Google's test IDs,
  release builds are signed with the debug key, and CORS allows every origin.
- Database migrations (tables are created with `metadata.create_all`; the production schema was
  changed by hand) and tests (there is one placeholder test).

## Goals

1. **Get the repository back in sync with production.** Copy the deployed API source from the
   Pi into this repository and commit it, along with the hand-made database changes
   (`trade_requests` table, `age_group` column). Recover the mobile code if any copy exists.
   Otherwise, rebuild the allowance-sharing screens from the description above.
2. **Full carpooling with allowance sharing.** Fix the open 3 L bug. Finish the trip lifecycle
   (completion, cancelling, ratings). Replace polling with real-time updates and push
   notifications, so the cargo declarations, trade requests and group allowance check work
   together reliably.
3. **Fix the bugs found while documenting the project:**
   - **The website uses the wrong API domain.** `website/calculator.js` calls
     `https://api.blablacase.com`, but the API lives at `https://api.blablacase.org`. On
     2026-11-13, `.org` answered `/health` with HTTP 200, while the TLS handshake to `.com`
     failed.
   - **The website calculator shows minors as allowed.** The API returns `per_minor: null` for
     "not allowed", but `calculator.js` replaces `null` with the adult value (`?? adultQty`) and
     checks for `undefined` instead of `null`. So minors are shown, and counted in the total, as
     if they had the adult allowance. The mobile app handles this correctly.
   - **A failed scrape overwrites the stored data.** The scraper's docstring says the database
     is left untouched when a scrape fails. In fact it writes the hard-coded reference values and
     updates `last_updated`, so the "up to date as of" date can be misleading.
   - **Declaration item types are out of date (in this repository).** `ALLOWED_ITEM_TYPES` in
     `declarations.py` still lists the original categories (`beer`, `fortified_wine`,
     `goods_value`) and does not include current ones such as `beverages_low` and `food_value`.
     The deployed version may already fix this; it can't be checked without its source.
   - The app only lets you create same-day trips, while the API accepts any return time after
     departure. The two should agree.
   - The 72-hour message limit only hides old messages; it should delete them.

## Why it's on hiatus

After the core features worked, the author spent time polishing (UI, splash screen, icons,
calculator source link) and then stepped back to look at the codebase as a whole. The
conclusion was that it needed a full rewrite rather than more patches. For example, the
declarations feature has drifted out of sync with the allowance categories, the trip-membership
check is copied into two routers, there are no migrations or tests (the production schema was
changed by hand), and chat is built on polling. Development is paused until that rewrite starts.
The API is still running in the meantime.

## Architecture

```
┌──────────────────┐      HTTPS + Firebase ID token      ┌───────────────────────────┐
│  Flutter app     │ ──────────────────────────────────▶ │  FastAPI (api/)           │
│  (Android)       │                                     │  on a Raspberry Pi,       │
│                  │ ◀── Firebase phone auth (SMS)       │  exposed via a Cloudflare │
└──────────────────┘                                     │  Tunnel                   │
┌──────────────────┐      GET /allowances (no auth)      │                           │
│  Static website  │ ──────────────────────────────────▶ │                           │
└──────────────────┘                                     └─────────────┬─────────────┘
                                                                       │ SQLAlchemy (asyncpg)
┌───────────────────────────┐   upsert allowance_items   ┌─────────────▼─────────────┐
│  Scheduler (api/scheduler)│ ─────────────────────────▶ │  PostgreSQL (Supabase)    │
│  DGDDI scraper, daily     │                            └───────────────────────────┘
└───────────────────────────┘
```

- **Mobile app (`mobile/`)**: Flutter, Material 3, dark theme. Riverpod for state, go_router
  for navigation (redirects to login when signed out), Dio for HTTP with an interceptor that
  attaches the Firebase ID token to every request.
- **API (`api/`)**: FastAPI with async SQLAlchemy 2. Every protected route verifies the Firebase
  ID token with the Firebase Admin SDK, and a user row is created the first time someone calls
  the API. Routers: `trips`, `users`, `messages`, `declarations`, `ratings`, `allowances`, plus
  `/health`. Production also has the trade-request endpoints (not in this repository).
- **DGDDI scraper (`api/jobs/scrape_dgddi.py`)**: finds the accordion section of the DGDDI page.
  Each section is parsed either as an HTML table or as inline `label : value unit` text. Units
  are normalised (cl → mL, kg → g), and an ordered rule table maps each row to an item type. Any
  item missing from the page keeps its hard-coded reference value. The scraper runs in its own
  process (`api/scheduler.py`, APScheduler), so it never runs once per API worker.
- **Website (`website/`)**: plain HTML/CSS/JS with no build step.

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Dart SDK ^3.10.4, Flutter ≥ 3.38), flutter_riverpod 2.6.1, go_router 14.8.1, dio 5.9.2, flutter_map 7.0.2, flutter_typeahead 5.2.0, shared_preferences 2.5.5, url_launcher 6.3.2, google_mobile_ads 5.3.1 |
| Android build | Android Gradle Plugin 8.11.1, Kotlin 2.2.20, Gradle 8.14, Java 17 |
| Auth | Firebase Auth (firebase_auth 5.7.0, firebase_core 3.15.2; firebase-admin 6.6.0 on the server) |
| API | Python 3.12, FastAPI 0.115.5, Uvicorn 0.32.1, Pydantic 2.10.3, SQLAlchemy 2.0.36 (async), asyncpg 0.30.0 |
| Scraping / jobs | httpx 0.28.1, APScheduler 3.10.4 |
| Database | PostgreSQL (hosted on Supabase) |
| Hosting | Docker Compose on a Raspberry Pi, public HTTPS through a Cloudflare Tunnel |
| Website | HTML, CSS, vanilla JavaScript |

Mobile versions are the ones resolved in `mobile/pubspec.lock`; Python versions are pinned in
`api/requirements.txt`.

## Running it

> Running this repository gives you the version **without** allowance sharing (see
> [Code that isn't in this repository](#code-that-isnt-in-this-repository)).

### API

You need Python 3.12, a PostgreSQL database and a Firebase project with phone auth enabled.

```bash
cp api/.env.example api/.env    # then fill in DATABASE_URL and the Firebase service account
pip install -r api/requirements.txt

# Load the variables from api/.env into your shell, then:
uvicorn api.main:app --reload   # API on http://localhost:8000 (interactive docs at /docs)
python3 -m api.scheduler        # in a second terminal: scrapes DGDDI now, then daily
```

`api/.env` is git-ignored. Never commit it.

### With Docker (how production runs)

```bash
docker compose up --build
```

This starts two containers from the same image: `api` (port 8000) and `scheduler`. Both read
`api/.env`. In production a Cloudflare Tunnel forwards public HTTPS traffic to port 8000; the
tunnel is not part of this repository.

### Mobile app

You need the Flutter SDK, an Android device or emulator, and your own Firebase Android config
(`mobile/android/app/google-services.json`, which is git-ignored).

```bash
cd mobile
flutter pub get
flutter run                      # debug build on a connected device
flutter build apk --release      # release APK
```

The API base URL is set in `mobile/lib/core/api/api_client.dart`.

### Website

Open `website/index.html` in a browser, or serve the folder with any static file server. The API
URL is the `API_BASE` constant at the top of `website/calculator.js` (it needs to be changed to
`.org`; see [Goals](#goals)).

## Author

Built solo by Thierry Bungaroo ([@CrackedOnTiti](https://github.com/CrackedOnTiti)) in April 2026.

BlaBlaCase is not affiliated with BlaBlaCar or with French customs.
