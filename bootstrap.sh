#!/usr/bin/env bash
set -euo pipefail

PROBE_DIR="${PROBE_DIR:-/opt/kuma-probes}"
PROBE_USER="${PROBE_USER:-kuma-probe}"

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Please run as root: sudo bash bootstrap.sh"
    exit 1
  fi
}

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    echo ""
  fi
}

install_pkgs() {
  local pm
  pm="$(detect_pm)"
  case "$pm" in
    apt)
      apt-get update -y
      apt-get install -y bash curl jq dnsutils util-linux ca-certificates
      ;;
    dnf)
      dnf install -y bash curl jq bind-utils util-linux ca-certificates
      ;;
    yum)
      yum install -y bash curl jq bind-utils util-linux ca-certificates
      ;;
    *)
      echo "Unsupported package manager. Please install: bash curl jq dig flock ca-certificates"
      exit 1
      ;;
  esac
}

ensure_user() {
  if ! id -u "$PROBE_USER" >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin "$PROBE_USER"
  fi
}

ensure_layout() {
  # 如果用户解压到别处，建议复制到 /opt/kuma-probes
  if [[ "$(realpath .)" != "$PROBE_DIR" ]]; then
    if [[ -e "$PROBE_DIR" ]]; then
      if [[ -d "$PROBE_DIR" ]]; then
        if dir_list="$(ls -A "$PROBE_DIR" 2>/dev/null)"; then
          if [[ -n "$dir_list" ]]; then
            if [[ "${PROBE_DIR_FORCE:-0}" == "1" ]]; then
              echo "PROBE_DIR_FORCE=1 set; overwriting $PROBE_DIR"
              rm -rf "$PROBE_DIR"
            else
              echo "Target $PROBE_DIR exists and is not empty."
              echo "Move/remove it or set PROBE_DIR_FORCE=1 to overwrite."
              exit 1
            fi
          fi
        else
          echo "Cannot read $PROBE_DIR; aborting."
          exit 1
        fi
      else
        if [[ "${PROBE_DIR_FORCE:-0}" == "1" ]]; then
          echo "PROBE_DIR_FORCE=1 set; overwriting $PROBE_DIR"
          rm -rf "$PROBE_DIR"
        else
          echo "Target $PROBE_DIR exists and is not a directory."
          echo "Move/remove it or set PROBE_DIR_FORCE=1 to overwrite."
          exit 1
        fi
      fi
    fi
    echo "Copying current directory to $PROBE_DIR ..."
    mkdir -p "$PROBE_DIR"
    cp -a . "$PROBE_DIR"
  fi

  if [[ ! -f "$PROBE_DIR/config.env" ]]; then
    echo "config.env not found, creating from config.env.example"
    cp -n "$PROBE_DIR/config.env.example" "$PROBE_DIR/config.env"
    echo "Please edit: $PROBE_DIR/config.env"
  fi

  chmod +x "$PROBE_DIR/run_all.sh" "$PROBE_DIR"/scripts/*.sh "$PROBE_DIR"/lib/*.sh 2>/dev/null || true
  chown -R "$PROBE_USER:$PROBE_USER" "$PROBE_DIR"
  chmod 600 "$PROBE_DIR/config.env" || true
}

install_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd not found. Use cron instead."
    exit 1
  fi

  cp -f "$PROBE_DIR/systemd/kuma-probes.service" /etc/systemd/system/kuma-probes.service
  cp -f "$PROBE_DIR/systemd/kuma-probes.timer" /etc/systemd/system/kuma-probes.timer

  systemctl daemon-reload
  systemctl enable --now kuma-probes.timer
}

need_root
install_pkgs
ensure_user
ensure_layout
install_systemd

echo "OK. Timer enabled."
systemctl status kuma-probes.timer --no-pager || true
echo "Logs: journalctl -u kuma-probes.service -n 100 --no-pager"
