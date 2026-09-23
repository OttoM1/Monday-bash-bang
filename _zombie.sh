#!/usr/bin/env bash

# (hardcoded path, adjust when needed)
# run 'whereis bash' in CLI to find your bash path

# pipeline in this script:
# toolchain check - env - metro - platforms - workspace - quality gate - green boot - freeze snapshot and results
set -uo pipefail

usage() {
  cat <<EOF
usage: ${0##*/} [-p ios|android|web] [-k] [-b] [-g] [-S]

  -p  platform (default: ios) — changes which native toolchain is required
  -k  kill whatever is holding Metro's port (8081)
  -b  boot an iOS simulator if none is running
  -g  shift-left: tsc + lint + tests before Metro
  -S  strict — warnings fail the run (CI default)
env: NO_COLOR=1, METRO_PORT=8081, CI=1
EOF
}
# colors:
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' DIM=$'\033[0;37m' NC=$'\033[0m'
else
  RED='' GREEN='' YELLOW='' DIM='' NC=''
fi
# echo functions:
pass() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; echo "PASS|$*" >>"$REPORT"; }
note() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*"; echo "WARN|$*" >>"$REPORT"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$NC" "$*"; echo "FAIL|$*" >>"$REPORT"; fails=$((fails + 1)); }
die()  { printf '\n%s%s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }
# default settings:
platform=ios
kill_port=0
boot_sim=0
run_gate=0
strict=0
if [ -n "${CI:-}" ]; then
  run_gate=1
  strict=1
fi
# _zombie args:
while getopts "p:kbgSh" opt; do
  case $opt in
    p) platform=$OPTARG ;;
    k) kill_port=1 ;;
    b) boot_sim=1 ;;
    g) run_gate=1 ;;
    S) strict=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
case $platform in ios|android|web) ;; *) die "unknown platform: $platform" ;; esac
# finds the expo/project root:
START_PWD=$PWD
_script=${BASH_SOURCE[0]:-$0}
case $_script in
  /*) SCRIPT_DIR=$(dirname "$_script") ;;
  *) SCRIPT_DIR=$(cd "$(dirname "$_script")" && pwd) ;;
esac
find_root() {
  local dir=$1
  while [ "$dir" != "/" ]; do
    [ -f "$dir/package.json" ] && { echo "$dir"; return 0; }
    dir=$(dirname "$dir")
  done
  return 1
}
ROOT=$(find_root "$START_PWD" || find_root "$SCRIPT_DIR") \
  || die "no package.json found. run me inside an expo project"
cd "$ROOT" || exit 1
grep -q '"expo"' package.json || die "no expo in $ROOT/package.json"
METRO_PORT=${METRO_PORT:-8081}
CACHE_DIR="$ROOT/node_modules/.cache/_until-green"
SNAPSHOT="$CACHE_DIR/toolchain.snapshot"
REPORT=$(mktemp -t _zombie.XXXXXX)
LOG=$(mktemp -t _zombie-log.XXXXXX)
fails=0
child=""
# metro cleanup:
cleanup() {
  [ -n "$child" ] && { pkill -P "$child" 2>/dev/null; kill "$child" 2>/dev/null; }
  rm -f "$REPORT" "$LOG"
}
trap cleanup EXIT
trap 'exit 130' INT

spin() {
  local frames=$'|/-\\' i=0
  [ -t 1 ] || return 0
  while kill -0 "$1" 2>/dev/null; do
    printf '\r%s %s' "${frames:i++%${#frames}:1}" "$2"
    sleep 0.1
  done
  printf '\r\033[K'
}
run_logged() {
  local label=$1; shift
  "$@" >"$LOG" 2>&1 &
  child=$!
  spin "$child" "$label"
  wait "$child"
  local rc=$?
  child=""
  return $rc
}
section() { printf '\n%s/\/\/\/\/\/\/\ %s /\/\/\/\/\/\/\%s\n\n' "$GREEN" "$*" "$NC"; }

# toolchain (SDK 53+ is tested on Node 20/22 LTS):
section "TOOLCHAIN"
if command -v node >/dev/null; then
  node_v=$(node -v)
  node_v=${node_v#v}
  node_maj=${node_v%%.*}
  sdk=""
  if [ -f node_modules/expo/package.json ]; then
    sdk=$(node -e "try{console.log(require('./node_modules/expo/package.json').version.split('.')[0])}catch(e){console.log('')}")
  fi

  if [ -n "$sdk" ] && [ "$sdk" -ge 53 ] 2>/dev/null && [ "$node_maj" -lt 20 ]; then
    fail "node $node_v is too old for Expo SDK $sdk (needs 20 or 22 LTS)"
  elif [ "$node_maj" -ge 24 ]; then
    note "node $node_v is newer than Expo SDK ${sdk:-?}'s tested LTS (20/22) — this is how 'works on my machine' starts"
  elif [ "$node_maj" = 21 ] || [ "$node_maj" = 23 ]; then
    note "node $node_v is odd-numbered; Expo tests 20/22 LTS"
  else
    pass "node $node_v${sdk:+  (expo sdk $sdk)}"
  fi
else
  fail "node not found"
fi
# manager:
if   [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
elif [ -f pnpm-lock.yaml ]; then pm=pnpm
elif [ -f yarn.lock ]; then pm=yarn
else pm=npm
fi
if command -v "$pm" >/dev/null; then
  pass "package manager $pm $($pm -v 2>/dev/null | head -1)"
else
  fail "lockfile wants $pm, but $pm is not on PATH"
fi

if command -v watchman >/dev/null; then
  pass "watchman $(watchman version 2>/dev/null | sed -n 's/.*"version": "\([^"]*\)".*/\1/p' | head -1)"
else
  note "watchman not installed — Metro will fall back to Node watching (slow on large trees)"
fi

if [ "$platform" = ios ] || [ "$platform" = web ]; then
  if command -v xcrun >/dev/null; then
    xcode_v=$(xcodebuild -version 2>/dev/null | awk '/Xcode/{print $2; exit}')
    pass "xcode ${xcode_v:-ok}"
  elif [ "$platform" = ios ]; then
    fail "no xcrun. ios simulator needs macOS + xcode"
  else
    note "xcode not found (ok for web-only)"
  fi
fi

if [ "$platform" = android ]; then
  if [ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]; then
    pass "android sdk ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
  else
    fail "ANDROID_HOME / ANDROID_SDK_ROOT not set"
  fi
  if command -v adb >/dev/null; then
    pass "adb $(adb version 2>/dev/null | head -1)"
  else
    fail "adb not on PATH"
  fi
fi
# env (values are hidden):
section "ENV CONTRACT"
if [ ! -f .env.example ]; then
  note "no .env.example — skipping key contract"
else
  missing=0
  empty=0
  checked=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key=${line%%=*}
    key=${key%%[[:space:]]*}
    [ -n "$key" ] || continue
    checked=$((checked + 1))
    if [ ! -f .env ]; then
      continue
    fi
    if ! grep -q "^${key}=" .env 2>/dev/null; then
      fail "missing key $key (declared in .env.example)"
      missing=$((missing + 1))
      continue
    fi
    val=$(grep "^${key}=" .env | head -1 | cut -d= -f2-)
    val=${val%\"}; val=${val#\"}; val=${val%\'}; val=${val#\'}
    if [ -z "$val" ]; then
      note "$key is empty — app boots, that feature is dead"
      empty=$((empty + 1))
    fi
  done < .env.example
  if [ ! -f .env ]; then
    fail ".env missing — copy .env.example and fill the keys ($checked required)"
  elif [ "$missing" = 0 ] && [ "$empty" = 0 ]; then
    pass "env contract  $checked keys present"
  elif [ "$missing" = 0 ]; then
    note "env contract  $checked keys, $empty empty (values never printed)"
  fi
fi
# metro:
section "METRO / PORT $METRO_PORT"
if command -v lsof >/dev/null; then
  pids=$(lsof -nP -t -iTCP:"$METRO_PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [ -n "$pids" ]; then
    show=""
    for pid in $pids; do
      cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
      show="$show $pid($cmd)"
    done
    if [ "$kill_port" = 1 ]; then
      for pid in $pids; do kill "$pid" 2>/dev/null || true; done
      sleep 0.3
      pass "killed listeners on :$METRO_PORT:$show"
    else
      note ":$METRO_PORT in use by$show  — rerun with -k to kill"
    fi
  else
    pass ":$METRO_PORT is free"
  fi
else
  note "lsof not found, skipping port check"
fi
# platforms:
section "DEVICES"
if [ "$platform" = ios ]; then
  if command -v xcrun >/dev/null; then
    booted=$(xcrun simctl list devices booted 2>/dev/null | grep -c Booted || true)
    if [ "${booted:-0}" -gt 0 ]; then
      names=$(xcrun simctl list devices booted 2>/dev/null | awk -F '[()]' '/Booted/{gsub(/^ +/,"",$1); print $1}' | paste -sd ', ' -)
      pass "ios simulator booted: $names"
    elif [ "$boot_sim" = 1 ]; then
      udid=$(xcrun simctl list devices available 2>/dev/null | awk '/iPhone/{if (match($0,/[0-9A-F-]{36}/)) {print substr($0,RSTART,RLENGTH); exit}}')
      if [ -n "$udid" ]; then
        xcrun simctl boot "$udid" >/dev/null 2>&1 || true
        open -a Simulator >/dev/null 2>&1 || true
        pass "booted ios simulator $udid"
      else
        fail "no available iPhone simulator to boot"
      fi
    else
      note "no ios simulator booted — Expo can launch one, or pass -b"
    fi
  fi
elif [ "$platform" = android ]; then
  if command -v adb >/dev/null; then
    devices=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}')
    if [ -n "$devices" ]; then
      pass "adb devices: $(echo "$devices" | paste -sd ', ' -)"
    else
      note "no android device/emulator online (adb devices is empty)"
    fi
  fi
else
  pass "web — no native device required"
fi
# workspace (npx expo start does not run npm prestart):
section "WORKSPACE PACKAGES"
stale=0
if [ -d packages ]; then
  for pkg_json in packages/*/package.json; do
    [ -f "$pkg_json" ] || continue
    dir=$(dirname "$pkg_json")
    name=$(node -e "try{console.log(require('./$pkg_json').name||'$dir')}catch(e){console.log('$dir')}")
    main=$(node -e "try{console.log(require('./$pkg_json').main||'')}catch(e){console.log('')}")
    [ -n "$main" ] || continue
    artifact="$dir/$main"
    if [ ! -f "$artifact" ]; then
      note "$name missing $main"
      stale=1
      continue
    fi
    newer=""
    if [ -d "$dir/src" ]; then
      newer=$(find "$dir/src" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) -newer "$artifact" -print 2>/dev/null | head -1)
    fi
    if [ -n "$newer" ]; then
      note "$name source newer than $main"
      stale=1
    else
      pass "$name  $main"
    fi
  done
  if [ "$stale" = 1 ]; then
    if grep -q '"build:packages"' package.json; then
      if run_logged "building workspace packages..." npm run build:packages; then
        pass "workspace packages rebuilt"
      else
        fail "workspace build failed"
        tail -n 20 "$LOG" >&2
      fi
    else
      fail "workspace artifacts stale and no build:packages script"
    fi
  fi
else
  pass "no packages/ workspace"
fi
# quality gate/CI:
if [ "$run_gate" = 1 ]; then
  section "QUALITY GATE"
  if [ -f tsconfig.json ]; then
    if run_logged "typecheck..." npx tsc --noEmit; then
      pass "tsc --noEmit"
    else
      fail "tsc --noEmit"
      tail -n 15 "$LOG" >&2
    fi
  else
    note "no tsconfig.json"
  fi

  if grep -q '"lint"' package.json; then
    if run_logged "lint..." npm run lint; then
      pass "lint"
    else
      fail "lint"
      tail -n 15 "$LOG" >&2
    fi
  fi

  if grep -q '"test"' package.json; then
    if run_logged "tests..." npm test; then
      pass "tests"
    else
      fail "tests"
      tail -n 15 "$LOG" >&2
    fi
  fi
fi
# last green boot (snapshot happens when we are actually green):
section "TOOLCHAIN DRIFT"
mkdir -p "$CACHE_DIR"
current=$(mktemp -t _zombie-now.XXXXXX)
{
  echo "node=${node_v:-none}"
  echo "pm=$pm"
  echo "expo=$(node -e "try{console.log(require('./node_modules/expo/package.json').version||'')}catch(e){console.log('none')}" 2>/dev/null)"
  echo "xcode=${xcode_v:-none}"
} >"$current"
if [ -f "$SNAPSHOT" ]; then
  drifted=0
  while IFS='=' read -r k old; do
    new=$(grep "^${k}=" "$current" | cut -d= -f2-)
    if [ "$old" != "$new" ]; then
      note "drift  $k  $old to $new  (last green boot)"
      drifted=1
    fi
  done < "$SNAPSHOT"
  [ "$drifted" = 0 ] && pass "toolchain matches last green boot"
else
  note "no previous snapshot — this run becomes the baseline"
fi
cp "$current" "$CACHE_DIR/toolchain.current"
rm -f "$current"
# results:
pass_n=$(grep -c '^PASS|' "$REPORT" || true)
warn_n=$(grep -c '^WARN|' "$REPORT" || true)
fail_n=$(grep -c '^FAIL|' "$REPORT" || true)
if [ "$strict" = 1 ] && [ "$warn_n" -gt 0 ]; then
  fails=$((fails + warn_n))
fi
printf '\n%s/\/\/\/\/\/\/\ _zombie  %s pass / %s warn / %s fail  (%ss) /\/\/\/\/\/\/\%s\n' \
  "$GREEN" "$pass_n" "$warn_n" "$fail_n" "$SECONDS" "$NC"
if [ "$fails" -gt 0 ]; then
  printf '%s/\/\/\/\/\/\/\ not admitting Metro. fix the ✗ lines, or drop -S / -g. /\/\/\/\/\/\/\%s\n\n' "$RED" "$NC"
  exit 1
fi
# toolchain freeze:
mv "$CACHE_DIR/toolchain.current" "$CACHE_DIR/toolchain.snapshot" 2>/dev/null || true
printf '\n'
exit 0
