#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

PUSH_URL="${KUMA_CLAUDE_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

start="$(ms_now)"
out="$(curl "${CURL_BASE[@]}" -o /dev/null -w '%{http_code} %{url_effective}' "https://claude.ai/" 2>&1)"
ec=$?
code=""
eff=""
if [[ $ec -eq 0 ]]; then
  code="${out%% *}"
  eff="${out#* }"
fi
ping="$(elapsed_ms "$start")"

loc="$(cf_loc)"
[[ -z "$loc" ]] && loc="UNK"
prefix="$(node_prefix)"

status="down"
if [[ $ec -ne 0 || -z "$eff" || -z "$code" ]]; then
  msg="Claude: Failed (Network) (${prefix}Egress:$loc)"
elif [[ "$code" =~ ^[45] ]]; then
  msg="Claude: Failed (HTTP $code) (${prefix}Egress:$loc)"
elif [[ "$eff" == "https://www.anthropic.com/app-unavailable-in-region" ]]; then
  msg="Claude: No (${prefix}Egress:$loc)"
elif [[ "$eff" == "https://claude.ai/" || "$eff" == https://claude.ai/* ]]; then
  status="up"
  msg="Claude: Yes (${prefix}Egress:$loc)"
else
  msg="Claude: Unknown ($eff) (${prefix}Egress:$loc)"
fi

push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
