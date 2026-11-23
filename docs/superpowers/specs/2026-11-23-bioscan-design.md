# /bioscan and meal logging: design

Status: draft for approval · 2026-11-23

## 1. Intent

One command, `/bioscan`, gives a full health log in Claude Code. It exists to help with, in priority order:

1. losing weight
2. stamina
3. lower resting heart rate
4. better habits
5. running for longer (running time)
6. speed, which matters least for now

It also learns the user's habits over time. Separately, meals are logged from an Android phone (photo, description, time the meal was finished) and get a calorie estimate. The Mac is closed most of the day, so meals sent from the phone must wait and be imported when the Mac is next opened.

Builds on what exists on branch `claude/hardening-and-health-check`:

- the Garmin connector (read-only, `GARMIN_READ_ONLY=true`)
- the Xiaomi scale connector (loopback HTTP, bearer token)
- `/health`
- `health-check/install.sh`

## 2. Goals

- **`/bioscan` on demand**, typed in Claude Code on the Mac, or from the phone through `claude remote-control` while the Mac is on. Sections are ordered by the user's priorities:
  1. weight
  2. calories eaten vs burned
  3. heart
  4. stamina
  5. sleep
  6. exercise
  7. speed
  8. habits noticed
  9. next steps
- **Changes since the last scan**, such as weight since the last `/bioscan`, alongside 7- and 30-day trends.
- **Exercise detail:** every run, walk and ride recorded on Garmin that day, each with start–end time, duration, distance and average pace (speed for rides), plus per-type totals for the day so far.
- **Meal inbox:** the phone drops photo + description + finish time into a Google Drive folder. When the Mac syncs, the next `/bioscan` imports every new meal. Claude estimates kcal, protein, carbs and fat, and stores the meal at the time the user gave.
- **Live meal logging:** while the Mac is on, `/meal` with a photo or description in the session gets an estimate immediately and logs it.
- **Habit learning:** each scan is saved. Claude looks across scans, meals and Garmin history for patterns and reports only patterns seen repeatedly, with their evidence.
- **Suggestions:** concrete next steps tied to the goals above, based on the data.

## 3. Non-goals

- Automatic delivery (scheduled reports, push, email). `/bioscan` runs when asked.
- Writing anything to Garmin Connect or Xiaomi. Garmin stays read-only; meals live in the local journal.
- Medical advice, or calorie precision beyond a photo estimate (expect ±20–30%).
- iPhone or Windows support for the meal inbox in this version.

## 4. Anti-goals (failure even if it "works")

- Inventing or filling in numbers that the data did not provide.
- Storing Garmin or Xiaomi passwords anywhere new.
- Importing the same meal twice, or losing a meal (an inbox file removed before its meal is safely in the journal).
- A slow, token-heavy scan. Raw Garmin payloads with per-minute arrays must not be pulled into the conversation, and arithmetic (totals, deltas, averages) is not left to the model.
- "Habits" that are one-off coincidences presented as patterns.

## 5. Constraints

- **Where it runs.** Everything runs on the user's Mac (macOS) in Claude Code, using skills and MCP servers registered at user scope by `install.sh`. The cloud session cannot reach Garmin or Xiaomi.
- **Phone access.** The phone reaches the Mac only through Remote Control, which needs the Mac awake with `claude remote-control` running.
  - Messages sent while the Mac is asleep are not known to queue.
  - Photo attachments are officially supported but have reported delivery bugs.
  - Hence the inbox.
- **Phone side:** Android with the Google Drive app.
- **Mac side:** Google Drive for desktop syncs `My Drive` to `~/Library/CloudStorage/GoogleDrive-<account>/My Drive/`. In streaming mode, files download when read.
- **Garmin data already available:**
  - daily summary, with calories burned (`totalKilocalories`, `activeKilocalories`)
  - sleep
  - activities by date (`activitylist-service` search: `activityType.typeKey`, `startTimeLocal`, `duration` s, `distance` m, `averageSpeed` m/s, `calories`)
  - VO2 max
  - training status and training readiness
- **Garmin repo conventions** (`CLAUDE.md`): no comments, DTO type + zod schema, `register*Tools`, `console.error` only, tests with vitest.

## 6. Approaches considered

How the phone reaches the Mac:

| Approach | Trade-offs | Decision |
|---|---|---|
| A. Claude app → remote-controlled session on the Mac | No new accounts or costs, data stays local. Needs the Mac awake; offline messages not known to queue; photo bugs reported. | **Chosen, with an inbox folder** so meals wait while the Mac is closed. Live chat still works when the Mac is on. |
| B. Telegram bot on the Mac | Reliable photo delivery, could push reports. Needs an Anthropic API key billed per use, a bot token and much more code; Telegram holds undelivered messages only about 24 h. | Rejected for now; fallback if A proves unreliable. |
| C. Cloud-hosted service | Works with the Mac closed. Garmin and Xiaomi logins would live in the cloud. | Rejected. |

How the Android phone fills the inbox:

| Approach | Trade-offs | Decision |
|---|---|---|
| Share sheet → Google Drive, with time and description in the file title | No extra apps; a few taps; title is editable in the "Save to Drive" dialog. | **Chosen.** |
| Google Form with photo upload | Text answers land in a Google Sheet, which Drive for desktop syncs only as a link file the Mac cannot read. | Rejected. |
| Automation apps (Tasker, MacroDroid) | One tap, but needs extra and often paid apps plus a separate sync app. | Rejected. |

Inside the Mac (builder's call, recorded here):

| Approach | Trade-offs | Decision |
|---|---|---|
| Small local **journal MCP server** for storage, inbox bookkeeping and arithmetic; Claude does photo estimation, insights and suggestions | A little more code, but file formats and numbers stay consistent and testable. | **Chosen.** |
| Skills only, with Claude editing journal files directly | Less code, but formats drift and sums are done by the model. | Rejected. |

## 7. Design

### 7.1 Phone flow (Android)

1. Take the photo with the camera as usual.
2. In the gallery: **Share → Drive**.
3. In "Save to Drive":
   - **Title:** `13:30 chicken rice, extra sauce`, i.e. the time the meal was finished, then a description.
   - **Folder:** `Health Inbox`.
4. Save. That's all; nothing else is needed until the Mac is opened.

Title rules:
- **Time format:** `HH:MM` 24 h; `1:30pm` is also accepted.
- **Date:** today. A time later than the upload time is treated as the previous day. `yesterday 21:00 pizza` is also understood.
- **No time in the title:** use the photo's capture time (EXIF), then the file's modified time. The meal is marked "time estimated".

A meal without a photo (description only) is shared as text from a notes app into the same folder. If Drive does not save shared text as a file, the fallback is any photo plus the description in the title. This is verified during setup.

### 7.2 Journal

Data lives in `~/health-check/data/` (mode 0700), separate from the code.

| File | Contents |
|---|---|
| `meals.jsonl` | One meal per line: `id`, `eaten_at` (local ISO time), `time_estimated`, `description`, `items[]` (each with `name`, `portion`, `kcal`, `protein_g`, `carbs_g`, `fat_g`), totals, `confidence` (`low`/`medium`/`high`), `source` (`inbox`/`chat`), `source_file`, `photo_sha256`, `logged_at`, `corrections[]`. |
| `days.jsonl` | One row per date, upserted: weight and body fat (if weighed), kcal eaten (from meals), kcal burned and active, resting HR, sleep minutes and score, steps, average stress, per-type minutes/km for runs, walks and rides, and the longest run. Each `/bioscan` fills today and backfills every day since the last scan (up to 30), so trends and habits have no gaps on days without a scan. |
| `scans.jsonl` | One line per `/bioscan`: `scanned_at`, plus the weight and day totals shown at the time, for the "since last scan" changes. |
| `habits.md` | Patterns Claude has seen repeatedly. Each entry has: statement, first seen, last seen, evidence count, examples. Rewritten by Claude after each scan; entries not supported for 30 days are removed. |
| `goals.json` | The priority order above, goal weight (from the scale's target if set, otherwise asked once), and daily calorie deficit target (default 500 kcal; see §10). |

Imported inbox files move to `Health Inbox/Imported/YYYY-MM-DD/` only after their meal is written. Files are never deleted. Re-import is prevented by `photo_sha256`, plus source file name for text items.

### 7.3 Journal MCP server

`health-check/journal/` is its own small TypeScript package, stdio transport, same stack as the Garmin connector. All tools are local file operations.

| Tool | Purpose |
|---|---|
| `list_inbox` | New items with their absolute file path, parsed time (and whether estimated), description and whether there is a photo. Unparseable items are listed with the reason. |
| `save_meal` | Validates the meal, appends it, then moves the inbox file. Idempotent. |
| `update_meal` | Applies a correction ("half portion", "no sauce"), keeping the original in `corrections[]`. |
| `get_meals` | Meals for a date, plus computed totals (kcal, protein, carbs, fat). |
| `get_last_scan` / `save_scan` | Read the previous scan; append a new one. |
| `save_days` | Upsert per-date rows (from the Garmin and Xiaomi tools); kcal eaten is filled in from the meals. |
| `get_history` | Daily rows for the last N days (default 30), with computed values: 7-day average deficit, resting HR trend, average sleep, weight change over 7 and 30 days, longest run and average run pace per week. |
| `get_goals` / `set_goals` | Read and change the targets. |
| `read_habits` / `write_habits` | The habits notes. |

All totals, deltas and averages are computed in code.

### 7.4 Garmin connector addition

Two new read-only tools that return compact data instead of raw Garmin records (the existing tools return full records, including per-minute arrays). Both take `startDate` and an optional `endDate`, so one call covers today or every day since the last scan.

`get_day_summaries(startDate, endDate)` returns one row per day, computed server-side from the daily summary and sleep:

- kcal burned and active
- resting HR and its 7-day average
- sleep minutes and score
- steps
- average stress
- Body Battery high/low

Field names are confirmed against the live account; missing fields come back as null.

`get_activity_log(startDate, endDate)` returns compact lines:

- **Grouping:**
  - Runs: `running`, `treadmill_running`, `trail_running`, `track_running`
  - Rides: `cycling`, `road_biking`, `mountain_biking`, `indoor_cycling`, `gravel_cycling`
  - Walks: `walking`, `hiking`
  - Anything else: "other", by name
- **Fields per activity:** start and end (local time), duration, distance in km, average pace in min/km (runs and walks) or speed in km/h (rides), and calories.
- **Totals:** per-group totals for the day.
- **Wiring:** reuses `getActivitiesByDate`, follows the repo conventions, unit-tested with fixture data. It is not one of the write tools, so read-only mode keeps it.

Performance data (VO2 max, training readiness, training status) comes from the existing tools if their payloads are small. If not, a compact `get_performance_snapshot` is added the same way. This is the builder's call after checking payload sizes against the live account.

### 7.5 `/bioscan` skill

Steps:

1. **Import meals:** `list_inbox`. For each item, read the photo, estimate items and macros from the photo plus description, then `save_meal`. Low-confidence estimates are marked "rough".
2. **Fetch:**
   - Garmin: `get_day_summaries` and `get_activity_log` from the day after the last scan through today (today only on the first scan), plus performance
   - Xiaomi: latest weigh-in and history
   - Journal: last scan, today's meals, 30-day history, habits, goals
3. **Show** the layout below. Leave out lines with no data; never estimate missing values.
4. **Save:** `save_days` for every fetched day, then `save_scan`.
5. **Update `habits.md`:** add or strengthen a pattern only with at least 3 supporting days; drop stale ones.

```
Bioscan · Tue 24 Nov   (last scan: Fri 20 Nov, 4 days ago)

Weight     84.2 kg · −0.6 since last scan · −2.1 in 30 days · goal 78
Calories   eaten 1,850 · burned 2,620 · deficit 770 (7-day avg 540, target 500)
Heart      resting 61 bpm (7-day avg 62 · a month ago 64)
Stamina    VO2 max 44 · longest run this week 38 min (last week 31)
Sleep      6h 40m, score 72 · week avg 6h 55m

Exercise today
  07:12–07:44  Run    32 min · 5.1 km · 6:16/km
  12:30–13:05  Walk   35 min · 2.9 km · 12:04/km
  18:02–19:07  Ride   1h 05 · 24.8 km · 22.9 km/h
  Totals: run 32 min / 5.1 km · walk 35 min / 2.9 km · ride 1h 05 / 24.8 km

Meals today (3 imported from your phone)
  08:10  Oats with banana            420 kcal
  13:30  Chicken rice, extra sauce   780 kcal  (rough)
  19:45  Salmon, potatoes, salad     650 kcal
  Protein 92 g · carbs 210 g · fat 61 g

Speed      avg run pace this week 6:20/km (last week 6:31)

Habits I've noticed
  - You eat about 400 kcal more on days after under 6 h of sleep (5 of the last 7 times).
  - Runs happen Tue/Thu/Sat; Mondays are usually inactive (4 of the last 4 weeks).

Next steps
  - Add an easy 25–30 min run on Monday at conversational pace.
  - Keep tomorrow's deficit near 500 kcal; aim for 110 g protein.
```

All numbers above are illustrative.

### 7.6 `/meal` skill (live, Mac on)

- **Logging:** with a photo and/or description in the message, estimate the meal, show the items with kcal and macros, then `save_meal` with `source: chat`. The meal time is the time given in the message, otherwise now.
- **Corrections:** `/meal fix <what>` corrects the most recent meal, or a named one, via `update_meal`.

### 7.7 `/health`

Stays as the quick check.

### 7.8 Installer

`install.sh` gains these steps:

- build `health-check/journal`
- create `~/health-check/data`
- find the Drive folder: detect `~/Library/CloudStorage/GoogleDrive-*/My Drive`, offer to create `Health Inbox` there, or ask for a path; store it in `goals.json`/config
- register `journal` with Claude Code
- install `/bioscan` and `/meal` with tool allowlists, including read access to the inbox folder for photos
- print the Android steps

Re-runs keep the data.

## 8. Failure handling

| Situation | Behaviour |
|---|---|
| Inbox item that can't be read or parsed | Left in the inbox and listed with the reason. |
| Drive folder missing or not synced | Say so, with the folder path, and carry on with the rest. |
| Garmin or Xiaomi unavailable | Show the remaining sections, with the same one-line fixes as `/health`. |
| No previous scan | "First scan"; changes start next time. |

## 9. Left to the builder

- Exact JSON field names and validation.
- The final activity-type grouping list.
- Whether a performance snapshot tool is needed.
- How skills reference the inbox path.
- Test fixtures.
- The wording of habit statements.

## 10. Decisions for the user (asked with this document)

1. **Units:** kg / km / min per km, or lb / miles / min per mile?
2. **Daily calorie deficit target:** default 500 kcal/day (about 0.5 kg or 1 lb a week). Keep it, or set your own, and set a goal weight if the scale doesn't have one.

## 11. To verify on the user's devices

- Android "Save to Drive" lets the title be edited and keeps the photo's capture time; whether shared text saves as a file.
- Google Drive for desktop path and streaming behaviour.
- Xiaomi S200 detected by the connector (still unverified).
- Photo attachments through Remote Control (live `/meal` from the phone).
