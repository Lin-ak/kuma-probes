#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_CLAUDE_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

support_claude() {
  local loc="$1"
  local support_list=(
    AL DZ AD AO AG AR AM AU AT AZ BS BH BD BB BE BZ BJ BT BO BA BW BR BN BG BF BI CV KH CM CA TD
    CL CO KM CG CR CI HR CY CZ DK DJ DM DO EC EG SV GQ EE SZ FJ FI FR GA GM GE DE GH GR GD GT GN
    GW GY HT HN HU IS IN ID IQ IE IL IT JM JP JO KZ KE KI KW KG LA LV LB LS LR LI LT LU MG MW MY
    MV MT MH MR MU MX FM MD MC MN ME MA MZ NA NR NP NL NZ NE NG MK NO OM PK PW PS PA PG PY PE PH
    PL PT QA RO RW KN LC VC WS SM ST SA SN RS SC SL SG SK SI SB ZA KR ES LK SR SE CH TW TJ TZ TH
    TL TG TO TT TN TR TM TV UG UA AE GB US UY UZ VU VA VN ZM ZW
  )
  local item
  for item in "${support_list[@]}"; do
    if [[ "$loc" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

start="$(ms_now)"
trace="$(curl_text "https://claude.ai/cdn-cgi/trace")"
ec=$?
ping="$(elapsed_ms "$start")"

status="down"
msg="Claude: Failed"

if [[ $ec -ne 0 ]]; then
  msg="Claude: Failed (Network)"
else
  region="$(printf '%s\n' "$trace" | awk -F= '/^loc=/{print $2; exit}')"
  region_uc="$(printf '%s' "$region" | tr '[:lower:]' '[:upper:]')"
  if [[ "$region_uc" == "T1" ]]; then
    status="up"
    msg="Claude: Yes (Region: TOR)"
  elif [[ -n "$region_uc" ]]; then
    if support_claude "$region_uc"; then
      status="up"
      msg="Claude: Yes (Region: $region_uc)"
    else
      msg="Claude: No (Region: $region_uc)"
    fi
  fi
fi

push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
