#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_CHATGPT_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

INSECURE="${INSECURE:-0}"

CHATGPT_UA_BROWSER="${CHATGPT_UA_BROWSER:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0}"
CHATGPT_SECCH_UA="${CHATGPT_SECCH_UA:-\"Microsoft Edge\";v=\"119\", \"Chromium\";v=\"119\", \"Not?A_Brand\";v=\"24\"}"

is_true() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

BASE_ARGS=( -sS -L --max-time "$TIMEOUT" -4 )
if is_true "$INSECURE"; then
  BASE_ARGS+=( -k )
fi
[[ -n "$PROXY" ]] && BASE_ARGS+=( --proxy "$PROXY" )
[[ -n "$NIC" ]] && BASE_ARGS+=( --interface "$NIC" )

curl_body_and_code() {
  local url="$1" ua="$2"; shift 2
  local marker="__HTTP_CODE__:"
  local out ec last
  out="$(curl "${BASE_ARGS[@]}" -A "$ua" "$@" -w $'\n'"$marker"'%{http_code}' "$url" 2>&1)"
  ec=$?
  last="$(printf '%s' "$out" | tail -n1)"
  if [[ "$last" == "$marker"[0-9][0-9][0-9] ]]; then
    CURL_CODE="${last#$marker}"
    CURL_BODY="$(printf '%s' "$out" | sed '$d')"
  else
    CURL_CODE=""
    CURL_BODY="$out"
  fi
  CURL_EC=$ec
}

curl_http_code() {
  local url="$1" ua="$2"; shift 2
  local out ec
  out="$(curl "${BASE_ARGS[@]}" -A "$ua" -o /dev/null -w '%{http_code}' "$@" "$url" 2>/dev/null)"
  ec=$?
  if [[ "$out" =~ ([0-9]{3})$ ]]; then
    CURL_CODE="${BASH_REMATCH[1]}"
  else
    CURL_CODE=""
  fi
  CURL_EC=$ec
}

get_country_code() {
  local url out loc
  for url in "$@"; do
    out="$(curl "${BASE_ARGS[@]}" "$url" 2>/dev/null)" || continue
    loc="$(printf '%s\n' "$out" | awk -F= '/^loc=/{print $2; exit}')"
    if [[ -n "$loc" ]]; then
      printf '%s' "$loc"
      return 0
    fi
  done
  printf 'UNK'
}

start="$(ms_now)"

api_headers=(
  -H "authority: api.openai.com"
  -H "accept: */*"
  -H "accept-language: zh-CN,zh;q=0.9"
  -H "authorization: Bearer null"
  -H "content-type: application/json"
  -H "origin: https://platform.openai.com"
  -H "referer: https://platform.openai.com/"
  -H "sec-ch-ua: $CHATGPT_SECCH_UA"
  -H "sec-ch-ua-mobile: ?0"
  -H 'sec-ch-ua-platform: "Windows"'
  -H "sec-fetch-dest: empty"
  -H "sec-fetch-mode: cors"
  -H "sec-fetch-site: same-site"
)

curl_body_and_code "https://api.openai.com/compliance/cookie_requirements" "$CHATGPT_UA_BROWSER" "${api_headers[@]}"
api_ec=$CURL_EC
api_code=$CURL_CODE
api_body=$CURL_BODY
hit_unsupported="false"
if [[ $api_ec -eq 0 && "$api_body" == *unsupported_country* ]]; then
  hit_unsupported="true"
fi

fav_headers=(
  -H "accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
  -H "origin: https://chatgpt.com"
  -H "referer: https://chatgpt.com/"
  -H "sec-ch-ua: $CHATGPT_SECCH_UA"
  -H "sec-ch-ua-mobile: ?0"
  -H 'sec-ch-ua-platform: "Windows"'
)

curl_http_code "https://chatgpt.com/favicon.ico" "$CHATGPT_UA_BROWSER" "${fav_headers[@]}"
fav_ec=$CURL_EC
fav_code=$CURL_CODE
web_blocked="false"
if [[ $fav_ec -eq 0 && "$fav_code" == "403" ]]; then
  web_blocked="true"
fi

country_code="$(get_country_code \
  "https://chat.openai.com/cdn-cgi/trace" \
  "https://chatgpt.com/cdn-cgi/trace" \
  "https://www.cloudflare.com/cdn-cgi/trace")"

ping="$(elapsed_ms "$start")"

state="Failed"
kuma_status="down"

if [[ $api_ec -eq 0 && $fav_ec -eq 0 ]]; then
  if [[ "$hit_unsupported" == "false" && "$web_blocked" == "false" ]]; then
    state="Yes"
    kuma_status="up"
  elif [[ "$hit_unsupported" == "true" && "$web_blocked" == "true" ]]; then
    state="No"
  elif [[ "$hit_unsupported" == "true" && "$web_blocked" == "false" ]]; then
    state="Website Only"
  elif [[ "$hit_unsupported" == "false" && "$web_blocked" == "true" ]]; then
    state="APP Only"
  else
    state="Failed"
  fi
fi

msg="ChatGPT: $state (Region: $country_code)"

if [[ "${DEBUG_CHATGPT:-0}" == "1" ]]; then
  echo "$msg"
  echo "apiExit=$api_ec apiCode=$api_code unsupported=$hit_unsupported | webExit=$fav_ec webCode=$fav_code | pingMs=$ping"
fi

push_kuma "$PUSH_URL" "$kuma_status" "$msg" "$ping"
