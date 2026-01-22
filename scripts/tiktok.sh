#!/usr/bin/env bash
# TikTok 区域检测（参考 MediaUnlockTest_Tiktok 逻辑，推送到 Uptime Kuma）
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_TIKTOK_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

UA_BROWSER="${UA_BROWSER:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36}"

extract_region() {
  local body="$1"
  local match
  match="$(printf '%s' "$body" | grep -oE '"region":"[A-Za-z]+"' | head -n1)"
  if [[ -n "$match" ]]; then
    printf '%s' "$match" | sed -E 's/.*"region":"([^"]+)".*/\1/'
    return 0
  fi
  return 1
}

start="$(ms_now)"

body="$(curl_text "https://www.tiktok.com/explore" -A "$UA_BROWSER")"
ec=$?
ping="$(elapsed_ms "$start")"

status="down"
msg="TikTok: No"

if [[ $ec -ne 0 ]]; then
  msg="TikTok: Failed (Network)"
elif [[ "$body" == *"https://www.tiktok.com/hk/notfound"* ]]; then
  msg="TikTok: No (Region: HK)"
else
  if region="$(extract_region "$body")"; then
    region_uc="$(printf '%s' "$region" | tr '[:lower:]' '[:upper:]')"
    status="up"
    msg="TikTok: Yes (Region: $region_uc)"
  fi
fi

push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
