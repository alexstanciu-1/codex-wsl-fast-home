#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./install.sh" >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-${USER}}"
WIN_CODEX_HOME="${WIN_CODEX_HOME:-/mnt/c/Users/${TARGET_USER}/.codex}"
FAST_CODEX_HOME="${FAST_CODEX_HOME:-/home/${TARGET_USER}/.codex-desktop-fast}"
CODEX_OWNER_USER="${CODEX_OWNER_USER:-${TARGET_USER}}"

if ! command -v rsync >/dev/null 2>&1; then
  apt-get update
  apt-get install -y rsync
fi

install -m 0755 bin/codex-fast-home-mount /usr/local/bin/codex-fast-home-mount

sed \
  -e "s#^Environment=WIN_CODEX_HOME=.*#Environment=WIN_CODEX_HOME=${WIN_CODEX_HOME}#" \
  -e "s#^Environment=FAST_CODEX_HOME=.*#Environment=FAST_CODEX_HOME=${FAST_CODEX_HOME}#" \
  -e "s#^Environment=CODEX_OWNER_USER=.*#Environment=CODEX_OWNER_USER=${CODEX_OWNER_USER}#" \
  systemd/codex-fast-home.service > /etc/systemd/system/codex-fast-home.service

systemctl daemon-reload
systemctl enable codex-fast-home.service
systemctl start codex-fast-home.service

systemctl status codex-fast-home.service --no-pager
findmnt -T "$WIN_CODEX_HOME" -o TARGET,SOURCE,FSTYPE
