#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ ! -f "$ROOT_DIR/config.env" ]]; then
  echo "config.env not found. Please copy config.env.example -> config.env and edit it."
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT_DIR/config.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/common.sh"

# 防止重叠运行（上一次没跑完下一次又启动）
LOCK_FILE="${LOCK_FILE:-$ROOT_DIR/.kuma-probes.lock}"
mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
if ! exec 9>"$LOCK_FILE"; then
  LOCK_FILE="/tmp/kuma-probes.lock"
  if ! exec 9>"$LOCK_FILE"; then
    exit 0
  fi
fi
flock -n 9 || exit 0

for s in "$ROOT_DIR"/scripts/*.sh; do
  [[ -f "$s" ]] || continue
  bash "$s" || true
done
