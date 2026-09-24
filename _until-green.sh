#!/usr/bin/env bash

# (hardcoded path, adjust when needed)
# run 'whereis bash' in CLI to find your bash path


# pipeline in this script:
# doctor - fix loop - expo launch
# one file, no dependencies. you can just drop this anywhere inside an expo project (i usually use ./bash)

set -uo pipefail
# left the "-e" out on purpose since the fix loop needs commands and room to fail
usage() {
  cat <<EOF
usage: ${0##*/} [-p ios|android|web] [-c] [-s] [-y] [-n]

  -p  platform to open (default: ios)
  -c  clear the metro cache
  -s  skip expo-doctor
  -y  non-interactive (skip the git y/n prompt)
  -n  stop after doctor/fix. no expo start
env: MAX_FIXES=16, NO_COLOR=1, CI=1
EOF
}
# colors:
  RED='\033[0;31m';
  GREEN='\033[0;32m';
  DIM='\033[0;36m';
  NC='\033[0m';
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  DIM=$'\033[0;37m'
  NC=$'\033[0m'
else
  RED='' GREEN='' DIM='' NC=''
fi
say()  { printf '\n%s%s%s\n' "$GREEN" "$*" "$NC"; }
dim()  { printf '\n%s%s%s\n' "$DIM" "$*" "$NC"; }
warn() { printf '\n%s%s%s\n' "$RED" "$*" "$NC" >&2; }
die()  { warn "$*"; exit 1; }

platform=ios
clear_cache=0
run_doctor=1
assume_yes=0
no_start=0
if [ -n "${CI:-}" ]; then
  assume_yes=1
  no_start=1
fi
while getopts "p:csynh" opt; do
  case $opt in
    p) platform=$OPTARG ;;
    c) clear_cache=1 ;;
    s) run_doctor=0 ;;
    y) assume_yes=1 ;;
    n) no_start=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
case $platform in ios|android|web) ;; *) die "unknown platform: $platform" ;; esac

# simple git check:
START_PWD=$PWD
_script=${BASH_SOURCE[0]:-$0}
case $_script in
  /*) SCRIPT_DIR=$(dirname "$_script") ;;
  *) SCRIPT_DIR=$(cd "$(dirname "$_script")" && pwd) ;;
esac

git_fail=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' DIM=$'\033[0;37m' NC=$'\033[0m'
else
  RED='' GREEN='' YELLOW='' DIM='' NC=''
fi
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$NC" "$*"; }
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bad "not inside a git repo"
  git_fail=1
else
  ROOT=$(git rev-parse --show-toplevel)
  cd "$ROOT" || exit 1
  printf "\n${GREEN}/\/\/\/\/\/\/\ GIT CONNECTION CHECK /\/\/\/\/\/\/\ ${NC}\n\n"
  printf 'in: %s\n\n' "$ROOT"
  echo -e "${DIM}remotes:${NC}"
  git remote -v | sed 's/^/  /'
  echo
  branch=$(git branch --show-current)
  if [ -z "$branch" ]; then
    bad "detached HEAD at $(git rev-parse --short HEAD)"
    git_fail=1
  else
    echo -e "${GREEN}on branch:${NC} $branch"
    case "$branch" in
      main|master) echo -e "${RED}\n/\/\/\/\/\/\/\ make sure the branch is where you want to be /\/\/\/\/\/\/\ ${NC}" ;;
    esac
  fi

  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || upstream=""
  if [ -n "$upstream" ]; then
    read -r behind ahead < <(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)
    if [ "${ahead:-0}" = 0 ] && [ "${behind:-0}" = 0 ]; then
      echo -e "${GREEN}\n/\/\/\/\/\/\/\ up to date with${NC} $upstream ${GREEN}/\/\/\/\/\/\/\ ${NC}\n"
    else
      warn "\n/\/\/\/\/\/\/\ $upstream: $ahead ahead, $behind behind /\/\/\/\/\/\/\ \n"
    fi
  else
    warn "\n/\/\/\/\/\/\/\ no upstream set for this branch /\/\/\/\/\/\/\ \n"
  fi

  if [ -z "$(git status --porcelain)" ]; then
    ok "working tree clean"
  else
    n=$(git status --porcelain | wc -l | tr -d ' ')
    echo -e "${YELLOW}\n/\/\/\/\/\/\/\ $n uncommitted change(s) /\/\/\/\/\/\/\${NC}"
    git status --short | sed 's/^/  /'
  fi
  echo
  git log -1 --format="${DIM}/\/\/\/\/\/\/\ last commit: %h %s (%cr) /\/\/\/\/\/\/\ ${NC}" 2>/dev/null || echo "/\/\/\/\/\/\/\ no commits yet /\/\/\/\/\/\/\ "
  cd "$ROOT" || exit 1
fi

if [ "$git_fail" = 1 ]; then
  printf '\n%s%s%s\n' "$RED" "/\/\/\/\/\/\/\ git check failed! stopping before doctor/fix/expo /\/\/\/\/\/\/\ " "$NC" >&2
  exit 1
fi
# git check ends here
warn() { printf '\n%s%s%s\n' "$RED" "$*" "$NC" >&2; }
DIM=$'\033[0;36m'
printf "\n\n${DIM}Git looking good?${NC} (y/n)\n";
read -n 1 -p "y/n: " go_doctor;

if [[ $go_doctor == "y" ]]; then {

# project root, should work from any subfolder :
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
# checks:
command -v node >/dev/null || die "node not found"
grep -q '"expo"' package.json || die "no expo in $ROOT/package.json, wrong folder?"
if [ "$platform" = ios ] && ! command -v xcrun >/dev/null; then
  die "no xcrun. the ios simulator needs macOS + xcode"
fi
# lock decides the project manager:
if   [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun
elif [ -f pnpm-lock.yaml ]; then pm=pnpm
elif [ -f yarn.lock ]; then pm=yarn
else pm=npm
fi
# safety guards:
attempt=0
max=${MAX_FIXES:-16} # max to 16, there is no need to set it any higher imo
child=""
LOG=$(mktemp -t _until-green.XXXXXX)
cleanup() {
  [ -n "$child" ] && { pkill -P "$child" 2>/dev/null; kill "$child" 2>/dev/null; }
  rm -f "$LOG"
}
trap cleanup EXIT
trap 'exit 130' INT
# runs while the pid is alive:
spin() {
  local frames=$'|/-\\' i=0
  [ -t 1 ] || return 0
  while kill -0 "$1" 2>/dev/null; do
    printf '\r%s %s' "${frames:i++%${#frames}:1}" "$2"
    sleep 0.1
  done
  printf '\r\033[K'
}
# output to the log:
deps_ok() {
  npx expo install --check --json >"$LOG" 2>&1 &
  child=$!
  spin "$child" "checking dependencies..."
  wait "$child"
  local rc=$?
  child=""
  return $rc
}
# CLI title echo:
say "/\/\/\/\/\/\/\ AUTOMATED NPM/NPX/EXPO LAUNCHER /\/\/\/\/\/\/\ "
dim "project: $ROOT ($pm)"
# doctor checks basic vulnerabilities:
  DIM='\033[0;36m';
if [ "$run_doctor" = 1 ]; then
  echo -e "${DIM}\nChecking for vulnerabilities. Please wait...${NC}"
  npx expo-doctor || warn "doctor found some things (see above), carrying on"
fi
# all pass?:
while ! deps_ok; do
  attempt=$((attempt + 1))
  if [ "$attempt" -gt "$max" ]; then
    warn "Still outdated after $max fixes. Last check said:"
    tail -n 20 "$LOG" >&2
    exit 1
  fi
  warn "Updates needed. Fix $attempt/$max, please wait..."
  npx expo install --fix "--$pm"
done
"$pm" install
args=("--$platform")
[ "$clear_cache" = 1 ] && args+=(--clear)
rm -f "$LOG"
if [ "$no_start" = 1 ]; then
  say "All dependencies up to date in ${SECONDS}s. Skipping Expo start (-n)."
  exit 0
fi
say "All dependencies up to date in ${SECONDS}s. Launching Expo $platform..."

exec npx expo start "${args[@]}"
}
else 
echo -e "${RED}\n\n/\/\/\/\/\/\/\ skipping doctor/fix/expo /\/\/\/\/\/\/\\n${NC}";
fi