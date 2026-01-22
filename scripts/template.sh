#!/usr/bin/env bash
# 新增脚本模板：复制此文件并改名为 xxx.sh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$ROOT_DIR/lib/common.sh"

# 1) 从 config.env 取该脚本的 push URL
PUSH_URL="${KUMA_XXX_PUSH:-}"
[[ -z "$PUSH_URL" ]] && exit 0

start="$(ms_now)"

# 2) 执行你的探测逻辑（下面是示例）
out="$(curl_text "https://example.com")"
ec=$?
ping="$(elapsed_ms "$start")"

region=""
if [[ $ec -eq 0 ]]; then
  region="$(cf_loc)"
fi

status="down"
if [[ -n "$region" ]]; then
  status="up"
else
  region="UNK"
fi

# 3) 推送到 Kuma
push_kuma "$PUSH_URL" "$status" "XXX: Region:$region" "$ping"
