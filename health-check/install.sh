#!/usr/bin/env bash
# Sets up the /health command for Claude Code: builds the Garmin and Xiaomi
# connectors, signs in to both, registers them with Claude Code and installs
# the command. Safe to re-run. Run with --help for options.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARMIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_DIR="$(cd "$GARMIN_DIR/.." && pwd)"
XIAOMI_DIR="${XIAOMI_DIR:-$BASE_DIR/xiaomi-scale-mcp}"
XIAOMI_REPO_URL="${XIAOMI_REPO_URL:-https://github.com/HexHub-web/xiaomi-scale-mcp}"
RUN_DIR="${HEALTH_CHECK_RUN_DIR:-$BASE_DIR/xiaomi-scale-run}"
XIAOMI_PORT="${XIAOMI_PORT:-8080}"
XIAOMI_BIN="$XIAOMI_DIR/target/release/xiaomi_scale_mcp"
CONFIG_FILE="$RUN_DIR/config.toml"
SKILL_DIR="$HOME/.claude/skills/health"
GARMIN_SESSION_FILE="$HOME/.garmin-mcp/oauth1_token.json"
SERVICE_LABEL="com.health-check.xiaomi-scale"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$SERVICE_LABEL.plist"
SYSTEMD_UNIT_NAME="health-check-xiaomi-scale.service"
SYSTEMD_UNIT="$HOME/.config/systemd/user/$SYSTEMD_UNIT_NAME"

MODE="install"
REGION=""
SKIP_SIGNIN=0
NO_SERVICE=0
OS="$(uname -s)"

usage() {
  cat <<'EOF'
Usage: health-check/install.sh [options]

Sets up the /health command in Claude Code for your Garmin and Xiaomi accounts.

Options:
  --region CODE     Xiaomi server region: de (Europe), us, sg, i2 (India), ru, cn.
                    Asked for on first install if omitted.
  --skip-signin     Do not run the Garmin and Xiaomi sign-in steps.
  --no-service      Do not start the Xiaomi connector automatically at login.
  --signin-garmin   Only sign in to Garmin again.
  --signin-xiaomi   Only sign in to Xiaomi again.
  --uninstall       Remove /health, both Claude Code connectors and the background service.
  -h, --help        Show this help.
EOF
}

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

ask_yes() {
  local answer
  read -r -p "$1 [Y/n] " answer || answer=""
  case "$answer" in
    [nN]*) return 1 ;;
    *) return 0 ;;
  esac
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --region) [ $# -ge 2 ] || die "--region needs a value"; REGION="$2"; shift ;;
      --skip-signin) SKIP_SIGNIN=1 ;;
      --no-service) NO_SERVICE=1 ;;
      --signin-garmin) MODE="signin-garmin" ;;
      --signin-xiaomi) MODE="signin-xiaomi" ;;
      --uninstall) MODE="uninstall" ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
  done
}

check_prereqs() {
  case "$OS" in
    Darwin|Linux) ;;
    *) die "this installer supports macOS and Linux only (found $OS)." ;;
  esac
  need git "Install Git first."
  need node "Install Node.js 20 or newer from https://nodejs.org"
  need npm "It comes with Node.js: https://nodejs.org"
  need cargo "Install Rust from https://rustup.rs (needed to build the Xiaomi connector)."
  need claude "Install the Claude Code command-line tool first: https://code.claude.com/docs"
  local node_major
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$node_major" -ge 20 ] || die "Node.js 20 or newer is required (found $(node --version))."
}

current_branch() {
  local branch
  branch="$(git -C "$GARMIN_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  [ "$branch" = "HEAD" ] && branch="main"
  printf '%s' "${HEALTH_CHECK_BRANCH:-$branch}"
}

ensure_xiaomi_repo() {
  if [ -d "$XIAOMI_DIR/.git" ]; then
    say "Xiaomi connector source: $XIAOMI_DIR (already present, not modified)"
    return
  fi
  local branch
  branch="$(current_branch)"
  step "Downloading the Xiaomi connector ($branch)"
  git clone --branch "$branch" "$XIAOMI_REPO_URL" "$XIAOMI_DIR"
}

build_garmin() {
  step "Building the Garmin connector"
  (cd "$GARMIN_DIR" && npm ci --no-fund --no-audit && npm run build)
}

build_xiaomi() {
  step "Building the Xiaomi connector (the first build takes several minutes)"
  (cd "$XIAOMI_DIR" && cargo build --release -p xiaomi_scale_mcp)
}

random_token() {
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

choose_region() {
  if [ -z "$REGION" ] && [ -f "$CONFIG_FILE" ]; then
    return
  fi
  if [ -z "$REGION" ]; then
    say ""
    say "Which Xiaomi server region does your Xiaomi Home app use?"
    say "  Europe: de   USA: us   Singapore / most of Asia: sg   India: i2   Russia: ru   China: cn"
    read -r -p "Region [de]: " REGION || REGION=""
    REGION="${REGION:-de}"
  fi
  case "$REGION" in
    [a-z][a-z]|[a-z][a-z0-9][a-z0-9]) ;;
    *) die "invalid region '$REGION' (expected something like de, us, sg)." ;;
  esac
}

write_xiaomi_config() {
  mkdir -p "$RUN_DIR/logs"
  chmod 700 "$RUN_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    if [ -n "$REGION" ]; then
      sed "s/^region = .*/region = \"$REGION\"/" "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
      mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
      chmod 600 "$CONFIG_FILE"
    fi
    say "Xiaomi connector settings: $CONFIG_FILE"
    return
  fi
  (
    umask 077
    cat > "$CONFIG_FILE" <<EOF
[server]
bind_address = "127.0.0.1:$XIAOMI_PORT"
allowed_hosts = ["localhost", "127.0.0.1", "::1"]
authorization_token = "$(random_token)"

[logging]
enabled = true
level = "info"
output = "file"
directory = "$RUN_DIR/logs"

[xiaomi]
sid = "xiaomiio"
region = "$REGION"
EOF
  )
  say "Created Xiaomi connector settings: $CONFIG_FILE"
}

read_token() {
  sed -n 's/^authorization_token = "\(.*\)"$/\1/p' "$CONFIG_FILE"
}

read_port() {
  sed -n 's/^bind_address = ".*:\([0-9][0-9]*\)"$/\1/p' "$CONFIG_FILE"
}

systemd_user_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

manual_start_command() {
  printf 'cd "%s" && MCP_CONFIG_PATH="%s" "%s"' "$RUN_DIR" "$CONFIG_FILE" "$XIAOMI_BIN"
}

start_xiaomi_hint() {
  if [ "$NO_SERVICE" -eq 1 ] && ! service_installed; then
    manual_start_command
    return
  fi
  # shellcheck disable=SC2016 # printed literally for the user to copy
  case "$OS" in
    Darwin) printf 'launchctl kickstart -k gui/$(id -u)/%s' "$SERVICE_LABEL" ;;
    *)
      if systemd_user_available; then
        printf 'systemctl --user restart %s' "$SYSTEMD_UNIT_NAME"
      else
        manual_start_command
      fi
      ;;
  esac
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

service_installed() {
  case "$OS" in
    Darwin) [ -f "$LAUNCHD_PLIST" ] ;;
    *) [ -f "$SYSTEMD_UNIT" ] ;;
  esac
}

stop_service() {
  service_installed || return 0
  case "$OS" in
    Darwin) launchctl bootout "gui/$(id -u)/$SERVICE_LABEL" >/dev/null 2>&1 || true ;;
    *) systemctl --user stop "$SYSTEMD_UNIT_NAME" >/dev/null 2>&1 || true ;;
  esac
}

start_service() {
  service_installed || return 0
  case "$OS" in
    Darwin)
      launchctl bootout "gui/$(id -u)/$SERVICE_LABEL" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST"
      ;;
    *)
      systemctl --user daemon-reload
      systemctl --user enable --now "$SYSTEMD_UNIT_NAME" >/dev/null
      systemctl --user restart "$SYSTEMD_UNIT_NAME"
      ;;
  esac
}

signin_garmin() {
  if [ "$MODE" != "signin-garmin" ] && [ -f "$GARMIN_SESSION_FILE" ]; then
    say "Garmin: already signed in (saved session in ~/.garmin-mcp)."
    return
  fi
  step "Signing in to Garmin"
  say "Your password is only sent to Garmin. The connector keeps a login token in ~/.garmin-mcp, not your password."
  node "$GARMIN_DIR/build/index.js" setup
}

signin_xiaomi() {
  [ -x "$XIAOMI_BIN" ] || die "the Xiaomi connector is not built yet. Run the full install first."
  [ -f "$CONFIG_FILE" ] || die "missing $CONFIG_FILE. Run the full install first."
  step "Signing in to Xiaomi"
  stop_service
  say "The Xiaomi connector will start in this terminal."
  say "  1. Type:  auth"
  say "  2. Enter your Xiaomi email/phone and password, plus any code Xiaomi asks for."
  say "  3. When you see 'Xiaomi account authorization succeeded.', press Ctrl+C."
  say "Your password is only sent to Xiaomi. The login token is stored in your system keychain."
  trap ':' INT
  (cd "$RUN_DIR" && MCP_CONFIG_PATH="$CONFIG_FILE" "$XIAOMI_BIN") || true
  trap - INT
  start_service
}

register_mcp() {
  step "Registering both connectors with Claude Code"
  local token port node_bin
  token="$(read_token)"
  port="$(read_port)"
  node_bin="$(command -v node)"
  [ -n "$token" ] || die "could not read authorization_token from $CONFIG_FILE"
  [ -n "$port" ] || die "could not read the port from bind_address in $CONFIG_FILE"
  claude mcp remove garmin -s user >/dev/null 2>&1 || true
  claude mcp remove xiaomi-scale -s user >/dev/null 2>&1 || true
  claude mcp add garmin -s user -e GARMIN_READ_ONLY=true -- "$node_bin" "$GARMIN_DIR/build/index.js"
  claude mcp add --transport http -s user xiaomi-scale "http://127.0.0.1:$port/mcp" \
    --header "Authorization: Bearer $token"
}

install_skill() {
  step "Installing the /health command"
  mkdir -p "$SKILL_DIR"
  local installer start_hint
  installer="$(escape_sed_replacement "$SCRIPT_DIR/install.sh")"
  start_hint="$(escape_sed_replacement "$(start_xiaomi_hint)")"
  sed -e "s|{{INSTALLER}}|$installer|g" \
      -e "s|{{START_XIAOMI}}|$start_hint|g" \
      "$SCRIPT_DIR/SKILL.md" > "$SKILL_DIR/SKILL.md"
  say "Installed: $SKILL_DIR/SKILL.md"
}

install_service() {
  step "Starting the Xiaomi connector automatically at login"
  case "$OS" in
    Darwin)
      mkdir -p "$(dirname "$LAUNCHD_PLIST")"
      cat > "$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$SERVICE_LABEL</string>
  <key>ProgramArguments</key><array><string>$XIAOMI_BIN</string></array>
  <key>WorkingDirectory</key><string>$RUN_DIR</string>
  <key>EnvironmentVariables</key>
  <dict><key>MCP_CONFIG_PATH</key><string>$CONFIG_FILE</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardInPath</key><string>/dev/null</string>
  <key>StandardOutPath</key><string>$RUN_DIR/logs/service.out.log</string>
  <key>StandardErrorPath</key><string>$RUN_DIR/logs/service.err.log</string>
</dict>
</plist>
EOF
      ;;
    *)
      if ! systemd_user_available; then
        say "systemd user services are not available here. Start the connector in a terminal you leave open:"
        say "  $(manual_start_command)"
        return
      fi
      mkdir -p "$(dirname "$SYSTEMD_UNIT")"
      cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=Xiaomi scale connector for Claude Code /health

[Service]
WorkingDirectory=$RUN_DIR
Environment=MCP_CONFIG_PATH=$CONFIG_FILE
ExecStart=$XIAOMI_BIN
StandardInput=null
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
      ;;
  esac
  start_service
  say "The Xiaomi connector now runs in the background and starts when you log in."
}

uninstall() {
  step "Removing /health and the connectors from Claude Code"
  if command -v claude >/dev/null 2>&1; then
    claude mcp remove garmin -s user >/dev/null 2>&1 || true
    claude mcp remove xiaomi-scale -s user >/dev/null 2>&1 || true
  fi
  rm -rf "$SKILL_DIR"
  stop_service
  case "$OS" in
    Darwin) rm -f "$LAUNCHD_PLIST" ;;
    *)
      if [ -f "$SYSTEMD_UNIT" ]; then
        systemctl --user disable "$SYSTEMD_UNIT_NAME" >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_UNIT"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
      fi
      ;;
  esac
  say "Removed. Left in place (delete them yourself if you want):"
  say "  - source code in $BASE_DIR"
  say "  - Xiaomi connector settings and cache in $RUN_DIR"
  say "  - Garmin login token in ~/.garmin-mcp"
  say "  - Xiaomi login token in your system keychain (entry 'xiaomi-scale-mcp');"
  say "    remove it by running the connector and typing: logout"
}

main() {
  parse_args "$@"
  case "$MODE" in
    uninstall) uninstall; return ;;
    signin-garmin)
      [ -f "$GARMIN_DIR/build/index.js" ] || die "the Garmin connector is not built yet. Run the full install first."
      signin_garmin
      return
      ;;
    signin-xiaomi) signin_xiaomi; return ;;
  esac

  check_prereqs
  ensure_xiaomi_repo
  build_garmin
  build_xiaomi
  choose_region
  write_xiaomi_config

  if [ "$SKIP_SIGNIN" -eq 0 ]; then
    signin_garmin
    if ask_yes "Sign in to Xiaomi now?"; then
      signin_xiaomi
    fi
  fi

  register_mcp
  install_skill

  if [ "$NO_SERVICE" -eq 0 ]; then
    install_service
  else
    say ""
    say "Start the Xiaomi connector in a terminal you leave open whenever you want to use /health:"
    say "  $(manual_start_command)"
  fi

  step "Done"
  say "Open Claude Code (the Code tab in the Claude desktop app, or run 'claude' in a terminal) and type:"
  say "  /health"
  say "If Claude Code was already open, restart it so it picks up the new connectors."
}

main "$@"
