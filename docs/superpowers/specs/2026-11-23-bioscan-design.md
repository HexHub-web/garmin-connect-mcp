# Jarvis: personal assistant for Claude Code, starting with fitness (`/bioscan`, meal logging)

Status: draft for approval, revision 2 · 2026-11-23

## 1. Intent

**Jarvis** is the user's personal assistant inside Claude Code. It is one named system with:
- its own MCP server
- its own commands
- its own repository

Its commands work in every Claude Code session on the user's Mac. It can be changed ("tweaked") from any new session.

The first module is fitness, which exists to help, in priority order, with:
1. losing weight
2. stamina
3. lower resting heart rate
4. better habits
5. running for longer (running time)
6. speed, which matters least for now

Planned later, as separate projects: habits and scheduling outside fitness. This version leaves room for them but does not build them.

The fitness module provides:

- **`/bioscan`:** a full health log that learns the user's habits over time.
- **Meal logging from an Android phone:** photo, description and the time the meal was finished, with a calorie estimate. The Mac is closed most of the day, so meals wait and are imported when the Mac is next opened.

Builds on branch `claude/hardening-and-health-check` of the user's forks:
- `garmin-connect-mcp`: read-only, `GARMIN_READ_ONLY=true`
- `xiaomi-scale-mcp`: loopback HTTP, bearer token

It also absorbs the existing `/health` command and installer.

## 2. Goals

- **Jarvis everywhere:**
  - The Jarvis MCP server and all Jarvis commands are installed for the user, so they work in every Claude Code session on the Mac (desktop app Code tab, terminal, or the phone via `claude remote-control`).
  - A `/jarvis` command lists the commands. When the user asks to change Jarvis from any session, it tells Claude where the code lives, the rules for changing it, and how to test, reinstall and save the change.
- **`/bioscan` on demand.** Sections are ordered by the user's priorities:
  1. weight
  2. calories eaten vs burned
  3. heart
  4. stamina
  5. sleep
  6. exercise
  7. today's meals
  8. speed
  9. habits noticed
  10. next steps
- **Changes since the last scan**, such as weight since the last `/bioscan`, alongside 7- and 30-day trends.
- **Exercise detail:** every run, walk and ride recorded on Garmin that day, each with start–end time, duration, distance and average pace (speed for rides), plus per-type totals for the day so far.
- **US units everywhere:**
  - pounds
  - miles
  - min/mile pace
  - mph
  - Calories (kcal)
  - grams for macros

  Data is stored in metric and converted only for display, so the unit setting can change later.
- **Meal inbox:** the phone drops photo + description + finish time into a Google Drive folder. When the Mac syncs, the next `/bioscan` imports every new meal. Claude estimates Calories, protein, carbs and fat, and stores the meal at the time the user gave.
- **Live meal logging:** while the Mac is on, `/meal` with a photo or description gets an estimate immediately and logs it.
- **Habit learning:** every day is recorded, including days without a scan. Claude reports only patterns seen on at least 3 days, with the evidence.
- **Suggestions:** concrete next steps tied to the priorities above.
  - There are no numeric targets for now: no goal weight, no Calorie target.
  - Suggestions are based on trends: keep a deficit going, more consistent sleep, longer easy runs.
  - Targets can be added later (`set_goals`).

## 3. Non-goals (this version)

- Habit tracking and scheduling outside fitness. These are later Jarvis modules; only the structure for them is built now.
- Automatic delivery (scheduled reports, push, email). Commands run when asked.
- Writing anything to Garmin Connect or Xiaomi. Garmin stays read-only; meals live in the Jarvis journal.
- Medical advice, or Calorie precision beyond a photo estimate (expect ±20–30%).
- iPhone or Windows support for the meal inbox.

## 4. Anti-goals (failure even if it "works")

- Inventing or filling in numbers that the data did not provide.
- Storing Garmin or Xiaomi passwords anywhere new.
- Importing the same meal twice, or losing a meal (an inbox file removed before its meal is safely in the journal).
- A slow, token-heavy scan. Raw Garmin payloads with per-minute arrays must not be pulled into the conversation, and arithmetic is not left to the model.
- "Habits" that are one-off coincidences presented as patterns.
- Personal data (journal, meal photos, tokens) ending up in the Jarvis repository.
- A structure that has to be rewritten to add the habits or scheduling modules.

## 5. Constraints

- **Where it runs.** Everything runs on the user's Mac (macOS) in Claude Code. The cloud session cannot reach Garmin or Xiaomi.
- **Phone access.** The phone reaches the Mac only through Remote Control, which needs the Mac awake with `claude remote-control` running.
  - Messages sent while the Mac is asleep are not known to queue.
  - Photo attachments are officially supported but have reported delivery bugs.
  - Hence the inbox.
- **Phone side:** Android with the Google Drive app.
- **Mac side:** Google Drive for desktop syncs `My Drive` to `~/Library/CloudStorage/GoogleDrive-<account>/My Drive/`. In streaming mode, files download when read.
- **Garmin data already available:**
  - daily summary, with Calories burned (`totalKilocalories`, `activeKilocalories`)
  - sleep
  - activities by date (`activitylist-service` search: `activityType.typeKey`, `startTimeLocal`, `duration` s, `distance` m, `averageSpeed` m/s, `calories`)
  - VO2 max
  - training status and training readiness
- **The Garmin and Xiaomi connectors stay in their own forks.** They keep their repo conventions; the Garmin repo's `CLAUDE.md` asks for no comments, DTO type + zod schema, `register*Tools`, `console.error` only, and vitest.

## 6. Approaches considered

How the phone reaches the Mac:

| Approach | Trade-offs | Decision |
|---|---|---|
| A. Claude app → remote-controlled session on the Mac | No new accounts or costs, data stays local. Needs the Mac awake; offline messages not known to queue; photo bugs reported. | **Chosen, with an inbox folder** so meals wait while the Mac is closed. |
| B. Telegram bot on the Mac | Reliable photo delivery, could push reports. Needs a per-use Anthropic API key, a bot token and much more code; Telegram holds undelivered messages only about 24 h. | Rejected for now; fallback if A proves unreliable. |
| C. Cloud-hosted service | Works with the Mac closed. Garmin and Xiaomi logins would live in the cloud. | Rejected. |

How the Android phone fills the inbox:

| Approach | Trade-offs | Decision |
|---|---|---|
| Share sheet → Google Drive, with time and description in the file title | No extra apps; a few taps. | **Chosen.** |
| Google Form | Answers land in a Google Sheet, which the Mac cannot read as a file. | Rejected. |
| Automation apps (Tasker, MacroDroid) | Extra and often paid apps plus a separate sync app. | Rejected. |

How Jarvis is put together (builder's call, recorded here):

| Approach | Trade-offs | Decision |
|---|---|---|
| **Own `jarvis` repository** with its own MCP server (modules inside), skills and installer; installs the Garmin and Xiaomi connectors as separate servers | Clean home for future modules; the connectors stay independent and updatable. | **Chosen.** |
| Grow everything inside the Garmin fork | Mixes non-Garmin and non-fitness features into a Garmin connector. | Rejected. |
| One Jarvis server that also wraps Garmin and Xiaomi | One server name, but couples a TypeScript server to a Rust one and duplicates their logins. | Rejected. |

Inside the Jarvis server:

| Approach | Trade-offs | Decision |
|---|---|---|
| Code does storage, inbox bookkeeping and arithmetic; Claude does photo estimation, insights and suggestions | Consistent, testable numbers and formats. | **Chosen.** |
| Skills only, with Claude editing files | Formats drift; sums done by the model. | Rejected. |

## 7. Design

### 7.1 Repository and layout

`github.com/HexHub-web/jarvis` is a new private repository. It is cloned to `~/jarvis` on the Mac.

```
jarvis/
  CLAUDE.md          how Jarvis is built and changed (read by every Claude session working on it)
  README.md          what Jarvis does, install, commands
  install.sh         one-time setup and re-install after changes (absorbs health-check/install.sh)
  server/            the Jarvis MCP server (TypeScript, stdio)
    src/modules/fitness/   meals, days, scans, inbox import, unit conversion
    src/modules/           future: habits/, schedule/
    src/core/              module registry, storage helpers, settings, units
  skills/            jarvis/, bioscan/, meal/, health/  → installed to ~/.claude/skills/
  docs/              designs (this document moves here)
```

The connectors are cloned next to it by `install.sh`, as today:
- `~/jarvis/connectors/garmin-connect-mcp`
- `~/jarvis/connectors/xiaomi-scale-mcp`

`connectors/` is git-ignored.

**Personal data never lives in the repo.**

| Data | Location |
|---|---|
| Journal | `~/.jarvis/` (mode 0700) |
| Garmin token | `~/.garmin-mcp/` |
| Xiaomi token | macOS keychain |
| Meal photos | the user's Google Drive |

**Claude Code registration (user scope):**

| Server | What it is |
|---|---|
| `jarvis` | the Jarvis server |
| `garmin` | the Garmin connector, read-only |
| `xiaomi-scale` | the Xiaomi connector, HTTP |

The existing `/health` setup is migrated by `install.sh`: it removes the old registrations and skill, and keeps the logins.

### 7.2 Modules

Each module registers its own tools under a prefix and owns its files under `~/.jarvis/<module>/`. Adding the habits or scheduling module means adding a folder and registering it; nothing else changes.

- **Now:** `fitness_*`.
- **Later:** `habits_*`, `schedule_*`.

`core` provides:
- atomic JSONL append and upsert
- settings (`~/.jarvis/settings.json`: units `us`, inbox path, priorities, optional targets)
- unit conversion

### 7.3 `/jarvis` and changing Jarvis from any session

- **`/jarvis` with no arguments** lists Jarvis's commands and where things live.
- **`/jarvis <change request>`** (or asking to change Jarvis in any session) loads instructions for Claude:
  1. the code is in `~/jarvis`; read its `CLAUDE.md` first
  2. make the change on a branch
  3. run the tests
  4. run `install.sh --update` to rebuild and reinstall, keeping data and logins
  5. commit, and push when the user asks
- **`CLAUDE.md`** documents:
  - the architecture
  - how to add a module, a tool or a command
  - code conventions
  - test and install commands
  - the security rules (no personal data in the repo, connectors read-only)
- **In cloud sessions** (claude.ai/code), the user selects the `jarvis` repository to change code there. The commands themselves only run on the Mac, where the logins are.

### 7.4 Phone flow (Android)

1. Take the photo.
2. **Share → Drive.**
3. In "Save to Drive":
   - **Title:** `1:30pm chicken rice, extra sauce`, i.e. the time the meal was finished, then a description.
   - **Folder:** `Jarvis Inbox`.
4. Save.

Title rules:
- **Time format:** `1:30pm` and `13:30` both work.
- **Date:** today. A time later than the upload time means the previous day. `yesterday 9pm pizza` is also understood.
- **No time in the title:** use the photo's capture time (EXIF), then the file's modified time. The meal is marked "time estimated".

A description-only meal is shared as text from a notes app into the same folder. If Drive does not save shared text as a file, the fallback is any photo plus the description in the title. This is verified during setup.

### 7.5 Fitness journal (`~/.jarvis/fitness/`)

| File | Contents |
|---|---|
| `meals.jsonl` | One meal per line: `id`, `eaten_at`, `time_estimated`, `description`, `items[]` (each with `name`, `portion`, `kcal`, `protein_g`, `carbs_g`, `fat_g`), totals, `confidence`, `source` (`inbox`/`chat`), `source_file`, `photo_sha256`, `logged_at`, `corrections[]`. |
| `days.jsonl` | One row per date, upserted: weight and body fat (if weighed), kcal eaten (from meals), kcal burned and active, resting HR, sleep minutes and score, steps, average stress, per-type minutes and distance for runs, walks and rides, and the longest run. Each `/bioscan` fills today and backfills every day since the last scan (up to 30). |
| `scans.jsonl` | One line per `/bioscan`: `scanned_at`, plus the weight and day totals shown, for the "since last scan" changes. |
| `habits.md` | Patterns seen on at least 3 days, each with statement, first and last seen, evidence count and examples. Entries unsupported for 30 days are removed. |

Imported inbox files move to `Jarvis Inbox/Imported/YYYY-MM-DD/` only after their meal is written. Files are never deleted. Re-import is prevented by `photo_sha256`, plus source file name for text items.

### 7.6 Jarvis server: fitness tools

| Tool | Purpose |
|---|---|
| `fitness_list_inbox` | New items with their absolute path, parsed time (and whether estimated), description and whether there is a photo; unparseable items with the reason. |
| `fitness_save_meal` | Validates the meal, appends it, then moves the inbox file. Idempotent. |
| `fitness_update_meal` | Applies a correction, keeping the original in `corrections[]`. |
| `fitness_get_meals` | Meals for a date with computed totals. |
| `fitness_save_days` | Upsert per-date rows from the Garmin and Xiaomi tools; kcal eaten filled in from the meals. |
| `fitness_get_last_scan` / `fitness_save_scan` | Read the previous scan; append a new one. |
| `fitness_get_history` | Daily rows for N days (default 30) with computed values: 7-day average deficit, resting HR trend, average sleep, weight change over 7 and 30 days, longest run and average run pace per week. Display values are already in US units. |
| `fitness_read_habits` / `fitness_write_habits` | The habits notes. |
| `jarvis_get_settings` / `jarvis_set_settings` | Shared settings: units, inbox path, priorities, optional targets. |

### 7.7 Garmin connector additions (in the Garmin fork)

Two new read-only tools that return compact data instead of full records with per-minute arrays. Both take `startDate` and an optional `endDate`.

`get_day_summaries` returns one row per day, computed from the daily summary and sleep:

- kcal burned and active
- resting HR and its 7-day average
- sleep minutes and score
- steps
- average stress
- Body Battery high/low

Field names are confirmed against the live account; missing fields come back as null.

`get_activity_log` returns one line per activity, in metric. Jarvis converts to US units.

- **Grouping:**
  - Runs: `running`, `treadmill_running`, `trail_running`, `track_running`
  - Rides: `cycling`, `road_biking`, `mountain_biking`, `indoor_cycling`, `gravel_cycling`
  - Walks: `walking`, `hiking`
  - Anything else: "other", by name
- **Fields per activity:** start and end (local time), duration, distance, average speed and calories.
- **Totals:** per-group totals per day.

Performance data (VO2 max, training readiness, training status) comes from the existing tools if their payloads are small. If not, a compact `get_performance_snapshot` is added the same way.

### 7.8 `/bioscan`

Steps:

1. **Import meals:** `fitness_list_inbox`. For each item, read the photo, estimate items and macros from the photo plus description, then `fitness_save_meal`. Low-confidence estimates are marked "rough".
2. **Fetch:**
   - Garmin: `get_day_summaries` and `get_activity_log` from the day after the last scan through today, plus performance
   - Xiaomi: latest weigh-in and history
   - Jarvis: last scan, today's meals, 30-day history, habits, settings
3. **Show** the layout below. Leave out lines with no data; never estimate missing values.
4. **Save:** `fitness_save_days` for every fetched day, then `fitness_save_scan`.
5. **Update habits:** add or strengthen a pattern only with at least 3 supporting days.

```
Jarvis · Bioscan · Tue Nov 24   (last scan: Fri Nov 20, 4 days ago)

Weight     185.6 lb · −1.3 since last scan · −4.6 in 30 days
Calories   eaten 1,850 · burned 2,620 · deficit 770 (7-day avg 540)
Heart      resting 61 bpm (7-day avg 62 · a month ago 64)
Stamina    VO2 max 44 · longest run this week 38 min (last week 31)
Sleep      6h 40m, score 72 · week avg 6h 55m

Exercise today
  7:12–7:44 am   Run    32 min · 3.17 mi · 10:06 /mi
  12:30–1:05 pm  Walk   35 min · 1.80 mi · 19:26 /mi
  6:02–7:07 pm   Ride   1h 05 · 15.4 mi · 14.2 mph
  Totals: run 32 min / 3.17 mi · walk 35 min / 1.80 mi · ride 1h 05 / 15.4 mi

Meals today (3 imported from your phone)
  8:10 am   Oats with banana            420 Cal
  1:30 pm   Chicken rice, extra sauce   780 Cal  (rough)
  7:45 pm   Salmon, potatoes, salad     650 Cal
  Protein 92 g · carbs 210 g · fat 61 g

Speed      avg run pace this week 10:12 /mi (last week 10:30)

Habits I've noticed
  - You eat about 400 Cal more on days after under 6 h of sleep (5 of the last 7 times).
  - Runs happen Tue/Thu/Sat; Mondays are usually inactive (4 of the last 4 weeks).

Next steps
  - Add an easy 25–30 min run on Monday at conversational pace.
  - Your 7-day deficit is steady; protein was low today (92 g).
```

All numbers above are illustrative.

### 7.9 `/meal` and `/health`

- **`/meal`** (Mac on): with a photo and/or description, estimate the meal, show the items with Calories and macros, then `fitness_save_meal` with `source: chat`. The meal time is the time given in the message, otherwise now. `/meal fix <what>` corrects a meal.
- **`/health`** stays as the quick check, now in US units, and moves into the Jarvis repo.

### 7.10 `install.sh`

- **First install** clones the connectors and builds all three servers.
- **Folders:**
  - creates `~/.jarvis`
  - finds the Drive folder: detects `~/Library/CloudStorage/GoogleDrive-*/My Drive`, offers to create `Jarvis Inbox`, or asks for a path
- **Sign-ins:** Garmin and Xiaomi, unless already signed in.
- **Claude Code:**
  - registers the three servers
  - installs `/jarvis`, `/bioscan`, `/meal` and `/health`, with tool allowlists that include read access to the inbox folder for photos
- **Background service:** the Xiaomi connector's LaunchAgent.
- **Finish:** prints the Android steps.
- **Migration:** removes the old `/health` install from the Garmin fork's `health-check/`.
- **`--update`** rebuilds and reinstalls, keeping data, settings and logins. It is what `/jarvis` runs after a change.
- **`--uninstall`** removes registrations and skills, and leaves data unless asked.

## 8. Failure handling

| Situation | Behaviour |
|---|---|
| Inbox item that can't be read or parsed | Left in the inbox and listed with the reason. |
| Drive folder missing or not synced | Say so, with the path, and carry on. |
| Garmin or Xiaomi unavailable | Show the remaining sections, with one-line fixes. |
| No previous scan | "First scan"; changes start next time. |

## 9. Left to the builder

- Exact JSON field names and validation.
- The final activity-type grouping.
- Whether a performance snapshot tool is needed.
- How skills reference the inbox path.
- Test fixtures.
- The wording of habit statements.
- The exact `CLAUDE.md` content.

## 10. Decided by the user

- US units everywhere.
- No numeric goals or targets for now.
- The system is named Jarvis, usable and changeable from every new Claude Code session.
- Habits and scheduling outside fitness come later as Jarvis modules.

## 11. Needed from the user before building

- Create the private repository `HexHub-web/jarvis` (empty: no README, license or .gitignore). This session cannot create repositories.

## 12. To verify on the user's devices

- Android "Save to Drive" title editing, capture time kept, and shared text saved as a file.
- Google Drive for desktop path and streaming behaviour.
- Xiaomi S200 detected by the connector (still unverified).
- Photo attachments through Remote Control (live `/meal` from the phone).
