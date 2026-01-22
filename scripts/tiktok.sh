#!/usr/bin/env bash
# TikTok 区域检测（参考 MediaUnlockTest_Tiktok 逻辑，推送到 Uptime Kuma）
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/config.env"
source "$ROOT_DIR/lib/common.sh"

# 可选：支持传参 4/6 强制 IPv4/IPv6
# 用法：
#   ./tiktok_region.sh        # 默认不强制
#   ./tiktok_region.sh 4      # 强制 IPv4
#   ./tiktok_region.sh 6      # 强制 IPv6
IP_VER="${1:-}"
CURL_IP_OPT=""
NAME_SUFFIX=""
case "$IP_VER" in
  4) CURL_IP_OPT="-4"; NAME_SUFFIX="(IPv4)" ;;
  6) CURL_IP_OPT="-6"; NAME_SUFFIX="(IPv6)" ;;
  "") ;;
  *)  # 传错参数就忽略，不中断
      IP_VER=""; CURL_IP_OPT=""; NAME_SUFFIX="" ;;
esac

# 1) 从 config.env 取 push URL（按需支持 v4/v6 两套）
# - 如果你只配一个，就用 KUMA_TIKTOK_PUSH
# - 如果你想 v4/v6 分开监控，可以分别配 KUMA_TIKTOK4_PUSH / KUMA_TIKTOK6_PUSH
if [[ "$IP_VER" == "4" ]]; then
  PUSH_URL="${KUMA_TIKTOK4_PUSH:-${KUMA_TIKTOK_PUSH:-}}"
elif [[ "$IP_VER" == "6" ]]; then
  PUSH_URL="${KUMA_TIKTOK6_PUSH:-${KUMA_TIKTOK_PUSH:-}}"
else
  PUSH_URL="${KUMA_TIKTOK_PUSH:-}"
fi
[[ -z "$PUSH_URL" ]] && exit 0

start="$(ms_now)"

# UA：如果你 common.sh 里已经定义了 UA_Browser，这里会沿用；否则用默认值
UA_Browser="${UA_Browser:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36}"

# 兼容你引用函数里的 curlArgs（比如代理/DoH 等），没有就为空
CURL_EXTRA="${curlArgs:-}"

# 2) 探测逻辑（参考 MediaUnlockTest_Tiktok）
# 2.1 先 GET 首页，取最终生效 URL
result="$(curl $CURL_EXTRA --user-agent "${UA_Browser}" ${CURL_IP_OPT:-} -fsSL --max-time 10 \
  --output /dev/null -w '%{url_effective}' "https://www.tiktok.com/" 2>&1)"
ec=$?

# 2.2 再 POST 获取 store_region
result1="$(curl $CURL_EXTRA --user-agent "${UA_Browser}" ${CURL_IP_OPT:-} -fsSL --max-time 10 \
  -X POST \
  -H "Referer: https://www.tiktok.com/" \
  -H "Origin: https://www.tiktok.com" \
  "https://www.tiktok.com/passport/web/store_region/" 2>&1)"
ec1=$?

# 解析 region（优先 jq；没有 jq 就用 sed 兜底）
region=""
if command -v jq >/dev/null 2>&1; then
  region="$(printf '%s' "$result1" | jq -r '.data.store_region // empty' 2>/dev/null | tr -d '"')"
else
  region="$(printf '%s' "$result1" | sed -n 's/.*"store_region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi

region_lc="$(printf '%s' "$region" | tr '[:upper:]' '[:lower:]')"
region_uc="$(printf '%s' "$region" | tr '[:lower:]' '[:upper:]')"
[[ -z "$region_uc" ]] && region_uc="UNKNOWN"

ping="$(elapsed_ms "$start")"

status="down"
prefix="TikTok${NAME_SUFFIX}"

# 3) 判断逻辑（对齐你参考函数的行为）
# curl 失败（result 里会是 curl: (xx) ...，且 ec!=0）
if [[ "$result" == curl* ]] || [[ $ec -ne 0 ]]; then
  if [[ "$IP_VER" == "6" ]]; then
    msg="${prefix}: IPv6 Not Support"
  else
    msg="${prefix}: Failed (Network Connection)"
  fi
else
  # 如果跳到 about/status/landing，视为不可用；其中 region=cn 认为是 “Provided by Douyin”
  if [[ "$result" == *"/about"* ]] || [[ "$result" == *"/status"* ]] || [[ "$result" == *"landing"* ]]; then
    if [[ "$region_lc" == "cn" ]]; then
      msg="${prefix}: Provided by Douyin"
    else
      msg="${prefix}: No (Region: ${region_uc})"
    fi
  else
    status="up"
    msg="${prefix}: Yes (Region: ${region_uc})"
  fi
fi

# 4) 推送到 Kuma
push_kuma "$PUSH_URL" "$status" "$msg" "$ping"
