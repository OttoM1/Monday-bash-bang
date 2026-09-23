#!/usr/bin/env bash

# (hardcoded path, adjust when needed)
# run 'whereis bash' in CLI to find your bash path


# pipeline in this script(run everything):
# 1. runs the _zombie script to check the toolchain
# 2. runs the _until-green script to check and fix deps + expo launch
# (the app script is more of a "beginner's tool" so i left it out of this)

set -uo pipefail

usage() {
  cat <<EOF
usage: ${0##*/} [-p ios|android|web] [-c] [-s] [-y] [-k] [-b] [-g] [-n] [-S]

  -p  platform to open (default: ios)
  -c  clear the metro cache
  -s  skip expo-doctor
  -y  non-interactive (skip the git y/n prompt)
  -k  kill whatever holds :8081
  -b  boot an iOS simulator if none is running
  -g  typecheck + lint + tests before Metro
  -n  stop after doctor/fix — no expo start (CI)
  -S  strict — _zombie warnings fail the run
env: MAX_FIXES=16, NO_COLOR=1, CI=1
EOF
}
# colors:
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' DIM=$'\033[0;37m' NC=$'\033[0m'
else
  RED='' GREEN='' YELLOW='' DIM='' NC=''
fi
# default settings:
platform=ios
clear_cache=0
run_doctor=1
assume_yes=0
kill_port=0
boot_sim=0
run_gate=0
no_start=0
strict=0
# CI mode:
if [ -n "${CI:-}" ]; then
  assume_yes=1
  no_start=1
  run_gate=1
  strict=1
fi
while getopts "p:csykbgnSh" opt; do
  case $opt in
    p) platform=$OPTARG ;;
    c) clear_cache=1 ;;
    s) run_doctor=0 ;;
    y) assume_yes=1 ;;
    k) kill_port=1 ;;
    b) boot_sim=1 ;;
    g) run_gate=1 ;;
    n) no_start=1 ;;
    S) strict=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
_script=${BASH_SOURCE[0]:-$0}
case $_script in
  /*) SCRIPT_DIR=$(dirname "$_script") ;;
  *) SCRIPT_DIR=$(cd "$(dirname "$_script")" && pwd) ;;
esac
[ -x "$SCRIPT_DIR/_zombie.sh" ] || chmod +x "$SCRIPT_DIR/_zombie.sh" "$SCRIPT_DIR/_until-green.sh" 2>/dev/null || true
# args for hulk smash (run everything):
pre_args=(-p "$platform")
[ "$kill_port" = 1 ] && pre_args+=(-k)
[ "$boot_sim" = 1 ] && pre_args+=(-b)
[ "$run_gate" = 1 ] && pre_args+=(-g)
[ "$strict" = 1 ] && pre_args+=(-S)
green_args=(-p "$platform")
[ "$clear_cache" = 1 ] && green_args+=(-c)
[ "$run_doctor" = 0 ] && green_args+=(-s)
[ "$assume_yes" = 1 ] && green_args+=(-y)
[ "$no_start" = 1 ] && green_args+=(-n)
# CLI title echo:
printf '\n%s/\/\/\/\/\/\/\ RUN EVERYTHING /\/\/\/\/\/\/\%s\n' "$GREEN" "$NC"
printf '%splatform=%s  gate=%s  start=%s%s\n\n' "$DIM" "$platform" \
  "$([ "$run_gate" = 1 ] && echo on || echo off)" \
  "$([ "$no_start" = 1 ] && echo no || echo yes)" "$NC"
t0=$SECONDS
"$SCRIPT_DIR/_zombie.sh" "${pre_args[@]}"
pre_rc=$?
pre_dt=$((SECONDS - t0))
if [ "$pre_rc" -ne 0 ]; then
  printf '\n%s/\/\/\/\/\/\/\ RUN ALL stopped at _zombie (%ss) /\/\/\/\/\/\/\%s\n' "$RED" "$pre_dt" "$NC"
  exit "$pre_rc"
fi
# toolchain snapshot only after a successful _zombie:
ROOT=""
dir=$PWD
while [ "$dir" != "/" ]; do
  if [ -f "$dir/package.json" ]; then ROOT=$dir; break; fi
  dir=$(dirname "$dir")
done
SNAP_DIR="$ROOT/node_modules/.cache/_until-green"
if [ -n "$ROOT" ] && [ -f "$SNAP_DIR/toolchain.current" ]; then
  mv "$SNAP_DIR/toolchain.current" "$SNAP_DIR/toolchain.snapshot"
fi
t1=$SECONDS
"$SCRIPT_DIR/_until-green.sh" "${green_args[@]}"
green_rc=$?
green_dt=$((SECONDS - t1))
if [ "$green_rc" -ne 0 ]; then
  printf '\n%s/\/\/\/\/\/\/\ RUN ALL  _zombie %ss  _until-green FAILED %ss /\/\/\/\/\/\/\%s\n' \
    "$RED" "$pre_dt" "$green_dt" "$NC"
  exit "$green_rc"
fi

printf '\n%s/\/\/\/\/\/\/\ RUN ALL  _zombie %ss  _until-green %ss  total %ss /\/\/\/\/\/\/\%s\n' \
  "$GREEN" "$pre_dt" "$green_dt" "$SECONDS" "$NC"
exit 0
