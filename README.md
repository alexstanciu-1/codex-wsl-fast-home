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

This is not a live two-way sync. After the bind mount is active, the fast ext4 directory is the primary store:

```text
/home/<wsl-user>/.codex-desktop-fast
```

The real Windows directory is only visible while the bind mount is inactive. If Codex or Windows writes files there while WSL is down, those files are not imported automatically after the fast store already exists. Use the explicit reset import flag when you intentionally want to merge Windows-side additions.

## What this patched version changes

This patched version keeps the original idea but changes the operational behavior:

- `codex-fast-home-mount` is mount-only and idempotent.
- It refuses unexpected existing mountpoints.
- It avoids duplicate/stacked bind mounts.
- It treats `/home/<wsl-user>/.codex-desktop-fast` as the source of truth after install.
- On first install only, when the fast mirror is empty, it imports the real Windows `.codex` into the fast ext4 mirror.
- During normal mount startup, it never syncs, deletes, or overwrites fast-mirror files.
- The systemd service is ordered before `multi-user.target` so WSL applies the mount as early as practical.
- `codex-fast-home-ensure` provides a preflight guard for startup races where Codex starts before the service finishes.
- A separate `codex-fast-home-reset` tool performs deliberate recovery: stop `Codex.exe`, unmount expected bind mounts, back up both sides, and mount again.
- `codex-fast-home-reset --import-windows-additions` explicitly imports Windows-side files that do not already exist in the fast mirror.

## Install

Clone the repo inside WSL:

```bash
git clone https://github.com/alexstanciu-1/codex-wsl-fast-home.git
cd codex-wsl-fast-home
sudo ./install.sh
```

The installer:

- Installs `bin/codex-fast-home-mount` to `/usr/local/bin`.
- Installs `bin/codex-fast-home-ensure` to `/usr/local/bin`.
- Installs `bin/codex-fast-home-reset` to `/usr/local/bin`.
- Installs and enables `codex-fast-home.service`.
- Creates `/home/<wsl-user>/.codex-desktop-fast`.
- Imports the current Windows `.codex` contents only if the fast directory is empty.
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

## Startup race guard

Codex Desktop can trigger WSL startup and then launch the WSL agent before systemd has finished starting every service. If that happens before this bind mount is active, early Codex writes may go to the real Windows `.codex` directory.

Use the ensure helper as close as possible to Codex agent startup:

```bash
codex-fast-home-ensure
```

The ensure helper:

1. Verifies that `/mnt/c/Users/<windows-user>/.codex` is mounted from `/home/<wsl-user>/.codex-desktop-fast`.
2. Refuses unexpected mount sources.
3. Attempts to start `codex-fast-home.service` if the mount is missing.
4. Waits briefly for the expected mount.
5. Fails loudly instead of silently allowing Codex to continue on the real Windows `.codex` path.

For a longer wait:

```bash
codex-fast-home-ensure --timeout 30
```

If the helper cannot start the service as a normal user, run one of:

```bash
sudo systemctl start codex-fast-home.service
sudo /usr/local/bin/codex-fast-home-mount
```

## Manual recovery / reset

Use this when Codex crashes or the bind mount needs to be cleaned up and reapplied:

```bash
sudo codex-fast-home-reset
```

The reset tool:

1. Calls Windows `taskkill.exe /IM Codex.exe /F` if WSL interop is available.
2. Unmounts only expected `FAST_CODEX_HOME -> WIN_CODEX_HOME` bind mounts, including stacked duplicates.
3. Refuses to unmount unexpected mount sources.
4. Backs up both the real Windows `.codex` and the fast mirror to `/home/<wsl-user>/codex-backups`.
5. Mounts the fast mirror once.

To explicitly import files created on the Windows side while WSL was down:

```bash
sudo codex-fast-home-reset --import-windows-additions
```

The import flag copies Windows-side files that do not already exist in the fast mirror. If the same relative file exists on both sides, the fast mirror wins.

## Manual install

Edit `systemd/codex-fast-home.service` if your Windows username differs from your WSL username, then:

```bash
sudo install -m 0755 bin/codex-fast-home-mount /usr/local/bin/codex-fast-home-mount
sudo install -m 0755 bin/codex-fast-home-ensure /usr/local/bin/codex-fast-home-ensure
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
- The fast ext4 mirror is the primary store after first install.
- Normal mount startup does not sync Windows `.codex` into the fast mirror.
- Reset does not import Windows-side files unless `--import-windows-additions` is passed.
- The mount and reset tools do not delete or overwrite files in the fast mirror.
- Review backups manually if you need to recover an older Windows-side version of an existing file.
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
