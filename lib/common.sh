#!/usr/bin/env bash
set -uo pipefail

: "${TIMEOUT:=10}"
: "${UA_BROWSER:=Mozilla/5.0}"
: "${PROXY:=}"
: "${PUSH_PROXY:=}"
: "${NIC:=}"
: "${NODE_NAME:=}"

# 统一 curl 基础参数（所有探测走同一出口/代理）
CURL_BASE=( -sS -L --max-time "$TIMEOUT" -A "$UA_BROWSER" -4 )
[[ -n "$PROXY" ]] && CURL_BASE+=( --proxy "$PROXY" )
[[ -n "$NIC"   ]] && CURL_BASE+=( --interface "$NIC" )

curl_text() {
  local url="$1"; shift
  local out
  out="$(curl "${CURL_BASE[@]}" "$@" "$url" 2>&1)"
  local ec=$?
  printf '%s' "$out"
  return $ec
}

curl_effective_url() {
  local url="$1"; shift
  local out ec
  out="$(curl "${CURL_BASE[@]}" "$@" -o /dev/null -w '%{url_effective}' "$url" 2>&1)"
  ec=$?
  if [[ $ec -ne 0 ]]; then
    printf ''
    return $ec
  fi
  printf '%s' "$out"
  return 0
}

# Cloudflare trace 取出口国家码（loc=XX）
cf_loc() {
  local out loc
  out="$(curl_text "https://www.cloudflare.com/cdn-cgi/trace")" || true
  loc="$(printf '%s\n' "$out" | awk -F= '/^loc=/{print $2; exit}')"
  printf '%s' "$loc"
}

ms_now() {
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
    return 0
  fi
  date +%s000
}

elapsed_ms() {
  local start="$1"
  local end
  end="$(ms_now)"
  if [[ -n "$start" && -n "$end" ]]; then
    echo $(( end - start ))
  else
    echo ""
  fi
}

node_prefix() {
  if [[ -n "$NODE_NAME" ]]; then
    printf 'Node:%s, ' "$NODE_NAME"
  else
    printf ''
  fi
}

# 推送到 Kuma（自动 URL encode）
push_kuma() {
  local push_url="$1" status="$2" msg="$3" ping="${4:-}"
  [[ -z "$push_url" ]] && return 0

  local args=( -sS --max-time 5 )

  # 推送代理优先级：PUSH_PROXY > PROXY > 直连
  if [[ -n "$PUSH_PROXY" ]]; then
    args+=( --proxy "$PUSH_PROXY" )
  elif [[ -n "$PROXY" ]]; then
    args+=( --proxy "$PROXY" )
  fi

  args+=( -G "$push_url"
          --data-urlencode "status=$status"
          --data-urlencode "msg=$msg" )
  [[ -n "$ping" ]] && args+=( --data-urlencode "ping=$ping" )

  curl "${args[@]}" >/dev/null 2>&1 || true
}
