#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_SUNLOGIN_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

HOST="${SUNLOGIN_HOST:-sunlogin.oray.com.w.kunluncan.com}"

start="$(ms_now)"
ip="$(dig +short A "$HOST" | head -n1)"
ping="$(elapsed_ms "$start")"

if [[ -z "$ip" ]]; then
  push_kuma "$PUSH_URL" "down" "Sunlogin: Failed" "$ping"
  exit 0
fi

# GeoIP（freeipapi；不需要 key，但有频率限制）
geo="$(curl_text "https://free.freeipapi.com/api/json/$ip")"
ec=$?
if [[ $ec -ne 0 ]]; then
  push_kuma "$PUSH_URL" "down" "Sunlogin: Failed" "$ping"
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  country="$(printf '%s' "$geo" | jq -r '.countryCode // ""')"
else
  country="$(printf '%s' "$geo" | grep -oE '"countryCode"\s*:\s*"[A-Za-z]{2}"' | head -n1 | sed -E 's/.*"([A-Za-z]{2})".*/\1/')"
fi

status="down"
if [[ -n "$country" ]]; then
  status="up"
  msg="Sunlogin: Yes (Region: $country)"
else
  msg="Sunlogin: Failed"
fi

push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
