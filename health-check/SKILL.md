---
name: health
description: Show my latest Garmin and Xiaomi scale data together in one short check-in (sleep, resting heart rate, stress, Body Battery, steps, weight and body composition). Use when I run /health or ask for my health check or latest stats.
argument-hint: "[YYYY-MM-DD]"
allowed-tools: mcp__garmin__get_daily_summary, mcp__garmin__get_sleep_data, mcp__xiaomi-scale__get_users, mcp__xiaomi-scale__get_historical_weights
---

# Health check

Give me one compact readout of my latest Garmin and Xiaomi scale data.

## Which day

Use `$ARGUMENTS` if it is a date in `YYYY-MM-DD` form. Otherwise use today's date in my local time zone.

## What to fetch

Make these read-only calls, in parallel where possible, and nothing else:

1. Garmin `get_daily_summary` for the day.
2. Garmin `get_sleep_data` for the day. Garmin files a night's sleep under the date you woke up, so this is last night's sleep.
3. Xiaomi `get_users`. Pick the profile with the most recent `last_weight_update_time_ms` (if there are several, mention the other profile names in one short line). Then call Xiaomi `get_historical_weights` with that `profile_id` and `page_size: 2` so you have the latest weigh-in and the one before it. Sort them yourself by `measured_at_seconds` (Unix seconds); do not assume the order.

Never call tools that change data, and do not call extra tools to fill gaps.

## How to show it

Use this layout. Leave out any line whose values are missing rather than printing nulls or zeros, and convert every timestamp to my local time.

```
Health check · <weekday> <day> <month>

Garmin  (synced <time of lastSyncTimestampGMT, if present>)
- Sleep: <h>h <m>m · score <overall score> (<qualifier>) · deep <h:mm> · REM <h:mm>
- Resting HR: <restingHeartRate> bpm (7-day avg <lastSevenDaysAvgRestingHeartRate>)
- Body Battery: <most recent> now · +<charged> / −<drained> today
- Stress: avg <averageStressLevel>
- Steps: <totalSteps> / <dailyStepGoal> · intensity minutes <moderate + 2×vigorous>
- SpO2: avg <averageSpo2>% · respiration <avgWakingRespirationValue> brpm

Scale  (<scale_name>, weighed <relative day and time>)
- Weight: <weight_kg> kg (<±change> kg since <date of previous weigh-in>)
- BMI <bmi> · body fat <body_fat_percent>% · muscle <muscle_mass_kg> kg · water <body_water_percent>%
- Visceral fat <visceral_fat> · BMR <basal_metabolic_rate_kcal> kcal · metabolic age <metabolic_age>
```

Then at most one sentence noting something that stands out in the numbers themselves (for example resting heart rate well above its 7-day average, or a short sleep). No medical advice, no generic tips. If nothing stands out, skip it.

If today's Garmin summary has no steps or heart rate yet, the watch has probably not synced: say "today not synced yet" on the Garmin line and still show last night's sleep.

## When something fails

Show whatever did work, never invent numbers, and add a one-line fix for each part that failed:

- Garmin tools missing, or an error mentioning `setup` or an expired session: "Sign in to Garmin again: `{{INSTALLER}} --signin-garmin`".
- Xiaomi tools missing, connection refused, or the connector is not running: "Start the Xiaomi connector: `{{START_XIAOMI}}`, then run `/mcp` here to reconnect".
- Xiaomi error saying the account is not authorized: "Sign in to Xiaomi: `{{INSTALLER}} --signin-xiaomi`".
- Xiaomi error starting with "No Xiaomi scale profiles were found": show that message as-is. It lists the device models on the account and is what is needed to add support for the scale.
