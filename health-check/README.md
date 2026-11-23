# /health for Claude Code

One command in Claude Code that shows your latest Garmin data (sleep, resting heart rate, stress, Body Battery, steps) and your latest Xiaomi scale reading (weight and body composition) together:

```
Health check · Mon 23 Nov

Garmin  (synced 07:42)
- Sleep: 7h 12m · score 81 (good) · deep 1:20 · REM 1:45
- Resting HR: 52 bpm (7-day avg 54)
- Body Battery: 85 now · +62 / −18 today
- Steps: 3,210 / 8,000

Scale  (Xiaomi Smart Scale S200, weighed today 07:15)
- Weight: 78.4 kg (−0.3 kg since 20 Nov)
- BMI 23.9 · body fat 18.2% · muscle 60.1 kg · water 55.0%
```

The numbers above are only an example of the layout.

## What you need

- macOS or Linux
- [Claude Code](https://code.claude.com/docs) with the `claude` command available in your terminal
- Node.js 20 or newer, Git, and Rust ([rustup.rs](https://rustup.rs)) to build the two connectors
- Your Garmin Connect account, and your Xiaomi account with the scale added in the **Xiaomi Home** app
- Linux only: a desktop keyring (GNOME Keyring or KWallet) for the Xiaomi login token

## Install

```bash
mkdir -p ~/health-check
git clone --branch claude/hardening-and-health-check https://github.com/HexHub-web/garmin-connect-mcp ~/health-check/garmin-connect-mcp
~/health-check/garmin-connect-mcp/health-check/install.sh
```

The installer:

1. Downloads the Xiaomi connector next to the Garmin one (`~/health-check/xiaomi-scale-mcp`) and builds both. The first Rust build takes several minutes.
2. Asks which Xiaomi server region your Xiaomi Home app uses (`de` for Europe, `us`, `sg`, `i2` for India, `ru`, `cn`).
3. Signs you in to Garmin, then to Xiaomi. You type your passwords into your own terminal; they go only to Garmin and Xiaomi. Afterwards only login tokens are kept: Garmin's in `~/.garmin-mcp`, Xiaomi's in your system keychain.
4. Registers both connectors with Claude Code for your user. Garmin runs in read-only mode, so nothing can change your Garmin account.
5. Installs the `/health` command in `~/.claude/skills/health`.
6. Starts the Xiaomi connector in the background whenever you log in (a LaunchAgent on macOS, a systemd user service on Linux). It only listens on `127.0.0.1` and needs a random access token that only Claude Code has.

Then open Claude Code (the Code tab in the Claude desktop app, or `claude` in a terminal) and type `/health`. Add a date to look at another day: `/health 2026-11-20`.

On macOS the first `/health` after install may show a keychain prompt for `xiaomi_scale_mcp`; choose **Always Allow**.

## Maintenance

| Task | Command |
|------|---------|
| Sign in to Garmin again | `~/health-check/garmin-connect-mcp/health-check/install.sh --signin-garmin` |
| Sign in to Xiaomi again | `~/health-check/garmin-connect-mcp/health-check/install.sh --signin-xiaomi` |
| Change the Xiaomi region | `~/health-check/garmin-connect-mcp/health-check/install.sh --skip-signin --region us` |
| Remove everything from Claude Code | `~/health-check/garmin-connect-mcp/health-check/install.sh --uninstall` |

## If your scale is not found

If `/health` says "No Xiaomi scale profiles were found", the message lists the device models on your Xiaomi account. Check the region first. If the region is right, the scale uses a model the connector does not support yet; that message is what is needed to add it.
