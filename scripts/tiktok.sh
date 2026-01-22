#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_TIKTOK_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

TIKTOK_URL="${TIKTOK_URL:-https://www.tiktok.com/}"
TIKTOK_UA="${TIKTOK_UA:-$UA_BROWSER}"
TIKTOK_LANG="${TIKTOK_LANG:-en-US,en;q=0.9}"

extract_region() {
  sed 's/\\"/"/g' | grep -oE '"region"\s*:\s*"[A-Za-z]{2}"' | head -n1 | sed -E 's/.*"([A-Za-z]{2})".*/\1/' | tr '[:lower:]' '[:upper:]'
}

start="$(ms_now)"
html="$(curl_text "$TIKTOK_URL" -A "$TIKTOK_UA")"
ec=$?
ping="$(elapsed_ms "$start")"

if [[ $ec -ne 0 ]]; then
  push_kuma "$PUSH_URL" "down" "TikTok: Failed" "$ping"
  exit 0
fi

region="$(printf '%s' "$html" | extract_region)"
if [[ -n "$region" ]]; then
  push_kuma "$PUSH_URL" "up" "TikTok: Yes (Region: $region)" "$ping"
  exit 0
fi

start2="$(ms_now)"
html2="$(curl_text "$TIKTOK_URL" --compressed \
  -A "$TIKTOK_UA" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9' \
  -H "Accept-Language: $TIKTOK_LANG")"
ec2=$?
ping2="$(elapsed_ms "$start2")"

if [[ $ec2 -ne 0 ]]; then
  push_kuma "$PUSH_URL" "down" "TikTok: Failed" "$ping2"
  exit 0
fi

region2="$(printf '%s' "$html2" | extract_region)"
if [[ -n "$region2" ]]; then
  push_kuma "$PUSH_URL" "up" "TikTok: Yes (Region: $region2)" "$ping2"
else
  push_kuma "$PUSH_URL" "down" "TikTok: Failed" "$ping2"
fi
