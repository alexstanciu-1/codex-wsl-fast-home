# Codex WSL Fast Home

Make Codex Desktop faster when the Windows app runs the agent in WSL2.

## Problem

Codex Desktop on Windows stores its home directory at:

```text
%USERPROFILE%\.codex
```

When the Desktop app is configured to run the Codex agent in WSL, that becomes:

```text
/mnt/c/Users/<you>/.codex
```

WSL2 access to `/mnt/c` is slow for lots of small file operations. Recent Codex versions may load plugins, skills, caches, sessions, and SQLite state from `.codex`, so a simple prompt can spend minutes in `Thinking` before the model response starts.

This workaround bind-mounts a native WSL ext4 directory over `/mnt/c/Users/<you>/.codex`. Codex Desktop still sees the same path, but WSL serves it from the fast Linux filesystem.

## Install

Clone the repo inside WSL:

```bash
git clone https://github.com/alexstanciu-1/codex-wsl-fast-home.git
cd codex-wsl-fast-home
sudo ./install.sh
```

The installer:

- Installs `bin/codex-fast-home-mount` to `/usr/local/bin`.
- Installs and enables `codex-fast-home.service`.
- Creates `/home/<you>/.codex-desktop-fast`.
- Copies the current Windows `.codex` contents into the fast directory if it is empty.
- Bind-mounts the fast directory over `/mnt/c/Users/<you>/.codex`.

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
TARGET                    SOURCE                                      FSTYPE
/mnt/c/Users/<you>/.codex /dev/sdX[/home/<you>/.codex-desktop-fast]   ext4
```

If `FSTYPE` is `9p` or the source is `C:\`, the bind mount is not active.

## Manual Install

Edit `systemd/codex-fast-home.service` if your Windows username differs from your WSL username, then:

```bash
sudo install -m 0755 bin/codex-fast-home-mount /usr/local/bin/codex-fast-home-mount
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
- It assumes `/mnt/c/Users/<you>/.codex` is the Codex Desktop home path.
- Quit Codex Desktop before the first install if possible, then reopen it after the mount is active.
- If you edit files under `%USERPROFILE%\.codex` from Windows while the bind mount is active, you are editing the WSL-backed directory through the mount.

## Uninstall

```bash
sudo systemctl disable --now codex-fast-home.service
sudo rm -f /etc/systemd/system/codex-fast-home.service
sudo rm -f /usr/local/bin/codex-fast-home-mount
sudo systemctl daemon-reload
```

If the mount is still active:

```bash
sudo umount /mnt/c/Users/$USER/.codex
```

The fast copy remains at:

```text
/home/<you>/.codex-desktop-fast
```
