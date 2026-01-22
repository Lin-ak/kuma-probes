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

support_gpt() {
  local loc="$1"
  local support_list=(
    AL DZ AD AO AG AR AM AU AT AZ BS BD BB BE BZ BJ BT BA BW BR BG BF CV CA CL CO KM CR HR CY DK
    DJ DM DO EC SV EE FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IQ IE IL IT JM
    JP JO KZ KE KI KW KG LV LB LS LR LI LT LU MG MW MY MV ML MT MH MR MU MX MC MN ME MA MZ MM NA
    NR NP NL NZ NI NE NG MK NO OM PK PW PA PG PE PH PL PT QA RO RW KN LC VC WS SM ST SN RS SC SL
    SG SK SI SB ZA ES LK SR SE CH TH TG TO TT TN TR TV UG AE US UY VU ZM BO BN CG CZ VA FM MD PS
    KR TW TZ TL GB
  )
  local item
  for item in "${support_list[@]}"; do
    if [[ "$loc" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

get_loc_from_trace() {
  local url="$1" ua="$2"; shift 2
  local loc
  curl_body_and_code "$url" "$ua" "$@"
  if [[ $CURL_EC -ne 0 ]]; then
    return 1
  fi
  loc="$(printf '%s\n' "$CURL_BODY" | awk -F= '/^loc=/{print $2; exit}')"
  if [[ -n "$loc" ]]; then
    printf '%s' "$loc"
    return 0
  fi
  return 1
}

start="$(ms_now)"

trace_headers=(
  -H "accept: */*"
  -H "accept-language: zh-CN,zh;q=0.9"
  -H "sec-ch-ua: $CHATGPT_SECCH_UA"
  -H "sec-ch-ua-mobile: ?0"
  -H 'sec-ch-ua-platform: "Windows"'
)

region=""
trace_urls=(
  "https://chat.openai.com/cdn-cgi/trace"
  "https://chatgpt.com/cdn-cgi/trace"
  "https://www.cloudflare.com/cdn-cgi/trace"
)
for url in "${trace_urls[@]}"; do
  if region="$(get_loc_from_trace "$url" "$CHATGPT_UA_BROWSER" "${trace_headers[@]}")"; then
    break
  fi
done

web_headers=(
  -H "accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  -H "accept-language: zh-CN,zh;q=0.9"
  -H "upgrade-insecure-requests: 1"
  -H "sec-ch-ua: $CHATGPT_SECCH_UA"
  -H "sec-ch-ua-mobile: ?0"
  -H 'sec-ch-ua-platform: "Windows"'
)

curl_body_and_code "https://chat.openai.com" "$CHATGPT_UA_BROWSER" "${web_headers[@]}"
web_ec=$CURL_EC
web_code=$CURL_CODE
web_body=$CURL_BODY

ping="$(elapsed_ms "$start")"

region_uc="$(printf '%s' "$region" | tr '[:lower:]' '[:upper:]')"
region_lc="$(printf '%s' "$region" | tr '[:upper:]' '[:lower:]')"

status="down"
msg="ChatGPT: Failed"

if [[ $web_ec -ne 0 ]]; then
  msg="ChatGPT: Failed (Network)"
elif [[ "$web_body" == *"VPN"* ]]; then
  msg="ChatGPT: VPN Blocked${region_uc:+ (Region: $region_uc)}"
elif [[ "$web_code" == "429" ]]; then
  msg="ChatGPT: Restricted (429)${region_uc:+ (Region: $region_uc)}"
elif [[ -n "$region_uc" ]]; then
  if support_gpt "$region_uc"; then
    status="up"
    msg="ChatGPT: Yes (Region: $region_uc)"
  else
    msg="ChatGPT: No (Region: $region_uc)"
  fi
fi

if [[ "${DEBUG_CHATGPT:-0}" == "1" ]]; then
  echo "$msg"
  echo "region=$region_lc pingMs=$ping http=$web_code"
fi

push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
