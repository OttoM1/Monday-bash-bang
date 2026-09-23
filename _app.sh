#!/usr/bin/env bash

# (hardcoded path, adjust when needed)
# run 'whereis bash' in CLI to find your bash path


# pipeline in this script:
# 1. basic beginner's tool checks: bash, git, node, npm
# 2. creates the expo project to desktop 'new-expo-app'
# 3. installs some basic native packages


# exit on error, let's get the basics installed first :D
set -uo pipefail
# set the root to the Desktop, easier to find imo
ROOT=$(cd ~/Desktop && pwd)
GREEN='\033[0;32m';
DIM='\033[0;36m';
RED='\033[0;31m';
NC='\033[0m';
FAIL=0
# bash:
if ! command -v bash >/dev/null 2>&1; then
  echo -e "\n${RED}Install bash - on Windows install git bash${NC} https://git-scm.com/downloads \n"
  FAIL=1
else
  echo -e "\n${GREEN}Bash OK:${NC} $(command -v bash)"
fi
# npm:
if ! command -v npm >/dev/null 2>&1; then
  echo -e "\n${RED}Install npm:${NC} https://nodejs.org/ \n"
  FAIL=1
else
  echo -e "\n${GREEN}Npm OK:${NC} $(command -v npm) ($(npm -v))\n"
fi
# node:
if ! command -v node >/dev/null 2>&1; then
  echo -e "${RED}Install Node.js:${NC} https://nodejs.org/\n"
  FAIL=1
else
  NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
  if [[ "$NODE_MAJOR" -lt 20 ]]; then
    echo -e "${RED}Node.js 20+ needed, currently${NC} $(node -v)\n"
    FAIL=1
  else
    echo -e "${GREEN}Node OK:${NC} $(node -v)\n"
  fi
fi
# git:
if ! command -v git >/dev/null 2>&1; then
  echo -e "${RED}Install git:${NC} https://git-scm.com/install/ \n"
  FAIL=1
else
  echo -e "${GREEN}Git OK:${NC} $(git --version)\n"
fi
# exit on error:
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

# strict mode for the expo project setup:
set -e
# you can adjust the "new-expo-app" name for the folder later:
ROOT="${ROOT}/new-expo-app"
APP_NAME="${1:-}"
if [ -n "$APP_NAME" ]; then
  echo -e "${DIM}Creating Expo project '${APP_NAME}' in ${ROOT}...${NC} \n"
else
  echo -e "${DIM}Creating Expo project in ${ROOT}\n (you will name it soon)...${NC}"
fi
mkdir -p "$ROOT"
cd "$ROOT"
if [ -n "$APP_NAME" ]; then
  npx create-expo-app@latest "$APP_NAME"
  cd "$APP_NAME"
else
  snapshot="$(mktemp)"
  ls -1d */ 2>/dev/null | sort >"$snapshot" || true
  npx create-expo-app@latest
  APP_NAME=""
  while IFS= read -r entry; do
    grep -qxF "$entry" "$snapshot" 2>/dev/null && continue
    APP_NAME="${entry%/}"
    break
  done < <(ls -1d */ 2>/dev/null | sort)
  rm -f "$snapshot"
  if [ -z "$APP_NAME" ] || [ ! -f "$APP_NAME/package.json" ]; then
    echo "Didn't find the new Expo app folder. Try: $0 my-app" >&2
    exit 1
  fi
  cd "$APP_NAME"
fi
# some basic packages i find useful, no matter the scope:
echo -e "${DIM}Installing baseline packages...\n${NC}"
npx expo install \
  expo-router \
  react-native-screens \
  react-native-safe-area-context \
  react-native-gesture-handler \
  react-native-reanimated \
  expo-image \
  expo-secure-store \
  expo-haptics \
  @expo/vector-icons

npm install -D prettier eslint-config-expo
echo -e "${GREEN}Setup complete!\n${NC}"
echo -e "You can find the project folder from Desktop (new-expo-app) or:\n"
echo -e "Run ${DIM}cd ${ROOT}/${APP_NAME} && npx expo start${NC} to begin.\n"