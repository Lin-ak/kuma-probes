#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_GEMINI_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

GEMINI_URL="${GEMINI_URL:-https://gemini.google.com}"
GEMINI_UA="${GEMINI_UA:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36}"
GEMINI_LANG="${GEMINI_LANG:-en-US,en;q=0.9}"

start="$(ms_now)"
body="$(curl_text "$GEMINI_URL" -A "$GEMINI_UA" -H "Accept-Language: $GEMINI_LANG" --max-redirs 10)"
ec=$?
ping="$(elapsed_ms "$start")"

region=""
if [[ $ec -eq 0 && "$body" == *"45631641,null"* ]]; then
  region="$(printf '%s' "$body" | grep -oE ',2,1,200,"[A-Z]{3}"' | head -n1 | sed -E 's/.*"([A-Z]{3})".*/\1/')"
fi

status="down"
if [[ -n "$region" ]]; then
  status="up"
else
  region="UNK"
fi

msg="Google Gemini: Region:$region"
push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
