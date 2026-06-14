#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "Run with sudo: sudo ./install.sh" >&2
	exit 1
fi

TARGET_USER="${CODEX_OWNER_USER:-${SUDO_USER:-${USER:-}}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
	cat >&2 <<'MSG'
Refusing to install codex-fast-home for user "root".

Run the installer from your normal WSL user:
  sudo ./install.sh

If this shell really must run as root, pass the intended WSL owner explicitly:
  sudo CODEX_OWNER_USER=<wsl-user> ./install.sh
MSG
	exit 1
fi

WIN_CODEX_HOME="${WIN_CODEX_HOME:-/mnt/c/Users/${TARGET_USER}/.codex}"
FAST_CODEX_HOME="${FAST_CODEX_HOME:-/home/${TARGET_USER}/.codex-desktop-fast}"
CODEX_OWNER_USER="${CODEX_OWNER_USER:-${TARGET_USER}}"

if ! command -v rsync >/dev/null 2>&1; then
	apt-get update
	apt-get install -y rsync
fi

install -m 0755 bin/codex-fast-home-mount /usr/local/bin/codex-fast-home-mount
install -m 0755 bin/codex-fast-home-ensure /usr/local/bin/codex-fast-home-ensure
install -m 0755 bin/codex-fast-home-reset /usr/local/bin/codex-fast-home-reset
install -m 0755 bin/codex-fast-home-doctor /usr/local/bin/codex-fast-home-doctor

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

cat <<'MSG'

Installed:
  /usr/local/bin/codex-fast-home-mount   # normal systemd/idempotent mount path
  /usr/local/bin/codex-fast-home-ensure  # preflight guard for startup races
  /usr/local/bin/codex-fast-home-doctor  # health check and optional repair
  /usr/local/bin/codex-fast-home-reset   # manual recovery: taskkill, unmount, backup, mount

Preflight guard example:
  codex-fast-home-ensure

Health check and self-repair example:
  codex-fast-home-doctor
  sudo codex-fast-home-doctor --repair

Manual recovery example:
  sudo codex-fast-home-reset

Explicit Windows-side import example:
  sudo codex-fast-home-reset --import-windows-additions
MSG
