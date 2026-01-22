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
region="$(cf_loc)"
ping="$(elapsed_ms "$start")"

status="down"
if [[ -n "$region" ]]; then
  status="up"
else
  region="UNK"
fi

msg="Claude: Region:$region"
push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
