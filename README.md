# Codex WSL Fast Home

Make Codex Desktop faster when the Windows app runs the agent in WSL2.

## Problem

Codex Desktop on Windows stores its home directory at:

```text
%USERPROFILE%\.codex
```

When the Desktop app is configured to run the Codex agent in WSL, that becomes:

```text
/mnt/c/Users/<windows-user>/.codex
```

WSL2 access to `/mnt/c` is slow for lots of small file operations.

Recent Codex versions may load plugins, skills, caches, sessions, and SQLite state from `.codex`, so a simple prompt can spend minutes in `Thinking` before the model response starts.

This workaround bind-mounts a native WSL ext4 directory over `/mnt/c/Users/<windows-user>/.codex`. Codex Desktop still sees the same path, but WSL serves it from the fast Linux filesystem.

## What this patched version changes

This patched version keeps the original idea but changes the operational behavior:

- `codex-fast-home-mount` is mount-only and idempotent.
- It refuses unexpected existing mountpoints.
- It avoids duplicate/stacked bind mounts.
- Before mounting, it synchronizes the real Windows `.codex` into the fast ext4 mirror with `rsync --delete`.
- A separate `codex-fast-home-reset` tool performs deliberate recovery: stop `Codex.exe`, unmount expected bind mounts, back up both sides, rebuild the fast mirror, and mount again.

## Install

Clone the repo inside WSL:

```bash
git clone https://github.com/alexstanciu-1/codex-wsl-fast-home.git
cd codex-wsl-fast-home
sudo ./install.sh
```

The installer:

- Installs `bin/codex-fast-home-mount` to `/usr/local/bin`.
- Installs `bin/codex-fast-home-reset` to `/usr/local/bin`.
- Installs and enables `codex-fast-home.service`.
- Creates `/home/<wsl-user>/.codex-desktop-fast`.
- Synchronizes the current Windows `.codex` contents into the fast directory before mounting.
- Bind-mounts the fast directory over `/mnt/c/Users/<windows-user>/.codex`.

If your Windows username is different from your WSL username, pass paths explicitly:

```bash
sudo WIN_CODEX_HOME=/mnt/c/Users/<windows-user>/.codex \
	FAST_CODEX_HOME=/home/<wsl-user>/.codex-desktop-fast \
	CODEX_OWNER_USER=<wsl-user> \
	./install.sh
```

## Verify

Run:

```bash
findmnt -T /mnt/c/Users/$USER/.codex -o TARGET,SOURCE,FSTYPE
```

Expected shape:

```text
TARGET                         SOURCE                                      FSTYPE
/mnt/c/Users/<user>/.codex     /dev/sdX[/home/<user>/.codex-desktop-fast]  ext4
```

If `FSTYPE` is `9p` or the source is `C:\`, the bind mount is not active.

## Manual recovery / reset

Use this only when Codex crashes, the `bin/wsl/codex/<hash>` folders diverge, or you need a clean rebuild of the fast mirror:

```bash
sudo codex-fast-home-reset
```

The reset tool:

1. Calls Windows `taskkill.exe /IM Codex.exe /F` if WSL interop is available.
2. Unmounts only expected `FAST_CODEX_HOME -> WIN_CODEX_HOME` bind mounts, including stacked duplicates.
3. Refuses to unmount unexpected mount sources.
4. Backs up both the real Windows `.codex` and the fast mirror to `/home/<wsl-user>/codex-backups`.
5. Rebuilds the fast mirror from the real Windows `.codex` with `rsync --delete`.
6. Mounts the fast mirror once.

## Manual install

Edit `systemd/codex-fast-home.service` if your Windows username differs from your WSL username, then:

```bash
sudo install -m 0755 bin/codex-fast-home-mount /usr/local/bin/codex-fast-home-mount
sudo install -m 0755 bin/codex-fast-home-reset /usr/local/bin/codex-fast-home-reset
sudo cp systemd/codex-fast-home.service /etc/systemd/system/codex-fast-home.service
sudo systemctl daemon-reload
sudo systemctl enable codex-fast-home.service
sudo systemctl start codex-fast-home.service
```

## Restart WSL

After Windows or WSL restarts, systemd should apply the mount automatically.

To test:

```powershell
wsl --shutdown
```

Then reopen WSL and run the `findmnt` verification command.

## Notes

- This is intended for WSL2 distributions with systemd enabled.
- It assumes `/mnt/c/Users/<windows-user>/.codex` is the Codex Desktop home path.
- Quit Codex Desktop before the first install if possible, then reopen it after the mount is active.
- Do not run the reset tool while you are intentionally relying on unsynced runtime state inside the fast mirror; reset rebuilds the fast mirror from the real Windows `.codex`.
- If you edit files under `%USERPROFILE%\.codex` from Windows while the bind mount is active, you are editing the WSL-backed directory through the mount.

## Uninstall

```bash
sudo systemctl disable --now codex-fast-home.service
sudo rm -f /etc/systemd/system/codex-fast-home.service
sudo rm -f /usr/local/bin/codex-fast-home-mount
sudo rm -f /usr/local/bin/codex-fast-home-reset
sudo systemctl daemon-reload
```

If the mount is still active:

```bash
sudo umount /mnt/c/Users/$USER/.codex
```

If duplicate bind mounts were stacked, repeat `umount` until it reports `not mounted` or use `findmnt` to verify.

The fast copy remains at:

```text
/home/<wsl-user>/.codex-desktop-fast
```
