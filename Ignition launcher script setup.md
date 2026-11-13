# `ignition.sh` — one-command launcher (Fedora KDE, Podman Compose + Toolbox)

`ignition.sh` replaces the manual steps for the Kanoa/Ignition dev stack:

| Manual steps | Script |
|---|---|
| `podman-compose up -d` | `ignition` |
| `podman-compose up -d --force-recreate kanoa` | `ignition recreate` |
| `toolbox enter ignition-designer`, `cd ...`, long `env ...` command | `ignition -d` |

**Tested on:** Fedora KDE 45 (Plasma, Wayland), `podman-compose`, Toolbox container `ignition-designer`, project `kanoa-docker-template`.

---

## Prerequisites

Everything below must already be in place (see the main setup guide):

1. The compose project (e.g. `~/projects/kanoa-docker-template`) with its `docker-compose.yaml` and `.env`.
2. A toolbox named `ignition-designer` with the GUI dependencies installed (`gtk3 libXtst libXxf86vm`).
3. Designer Launcher extracted under `~/ignition-designer/`.
4. `podman-compose`, `toolbox` and `curl` available on the host.

---

## One-time setup

### 1. Put the script next to `docker-compose.yaml`

```bash
cp /path/to/ignition.sh ~/projects/kanoa-docker-template/ignition.sh
chmod +x ~/projects/kanoa-docker-template/ignition.sh
```

The script finds the compose project by looking at its own folder first, so no configuration is needed in this layout.

> Every time you **replace** the file with a fresh copy (download, `cp` from elsewhere), run `chmod +x` again — a new copy has no execute permission.

### 2. Make the `ignition` command available everywhere

```bash
mkdir -p ~/.local/bin
ln -sf ~/projects/kanoa-docker-template/ignition.sh ~/.local/bin/ignition
```

Use a **symlink**, not a copy: the script resolves the link and still finds the compose project. If `ignition` is "command not found", `~/.local/bin` is not in your `PATH`: open a new terminal, or run `source ~/.bashrc`.

### 3. Check that it works

```bash
ignition          # containers start, "Gateway is running" appears
ignition -d       # Designer Launcher window opens
```

---

## Daily use

Run on the **host**, not inside a toolbox (the script refuses to run inside one).

| Command | What it does |
|---|---|
| `ignition` | `podman-compose up -d`, then waits until the Gateway answers. Does **not** open Designer |
| `ignition -d` | Opens Designer Launcher in the toolbox (also `--designer`, `designer`) |
| `ignition recreate [service]` | `up -d --force-recreate <service>` (default `kanoa`), then waits for the Gateway |
| `ignition stop` | `podman-compose stop` — containers and data are kept |
| `ignition status` | `podman-compose ps` and Gateway state |
| `ignition logs [service]` | Follows logs (default `kanoa`) |
| `ignition --help` | Prints the help text |

Typical order: `ignition` → wait for `Gateway is running` → `ignition -d`.

The script never runs `down -v`, so the SQL Server volume is never deleted by it.

---

## Settings (environment variables)

All optional.

| Variable | Default | Purpose |
|---|---|---|
| `IGNITION_COMPOSE_DIR` | folder of the script, then current folder | Compose project location (needed only if the script is not stored in it) |
| `IGNITION_URL` | `http://localhost:8088` | Address used for the Gateway readiness check |
| `IGNITION_WAIT` | `240` | Seconds to wait for the Gateway |
| `IGNITION_TOOLBOX` | `ignition-designer` | Toolbox container name |
| `IGNITION_LAUNCHER_ROOT` | `~/ignition-designer` | Where to search for `designerlauncher.sh` |
| `IGNITION_LAUNCHER_DIR` | _(auto-detect)_ | Optional override: exact folder containing `designerlauncher.sh`. Not needed normally |

Example: `IGNITION_URL=http://kanoa-dev.localtest.me ignition`

---

## What `ignition -d` actually runs

Equivalent to entering the toolbox and running:

```bash
cd <launcher folder>
env -u WAYLAND_DISPLAY mesa_glthread=false _JAVA_AWT_WM_NONREPARENTING=1 \
  JAVA_TOOL_OPTIONS="-Dawt.robot.screenshotMethod=x11 -Dsun.java2d.xrender=false" \
  ./designerlauncher.sh
```

(see the main setup guide for what each setting does). The script starts it with `toolbox run ... 2>&1 | cat`. The `| cat` is intentional: on the tested machine the launcher window did **not** open when the output went straight to the terminal, and opened normally when the output was piped. This (not the choice of launcher folder) was the cause of the "nothing happens" problem; why it matters was not investigated, so don't remove it. With it in place, the launcher folder is found automatically on the tested machine, with no override.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Permission denied` when running `ignition` | The script lost its execute bit after being replaced: `chmod +x ~/projects/kanoa-docker-template/ignition.sh` |
| `ignition: command not found` | `~/.local/bin` is not in `PATH` (open a new terminal / `source ~/.bashrc`), or the symlink is missing: `ls -l ~/.local/bin/ignition` |
| `You are inside a toolbox` | Run `exit` and use the script on the host |
| `No compose file found` | Script is not in the compose folder: set `IGNITION_COMPOSE_DIR=/path/to/project` |
| `Gateway did not answer at ... in 240s` | Wrong address (e.g. you use a Traefik hostname instead of `localhost:8088`): set `IGNITION_URL`. The containers are still running; this is only a warning |
| `ignition -d` prints `Opening Designer Launcher from ...` and nothing happens | Check the folder shown in that line. If it is not the one that works for you, point the script at the right one with `IGNITION_LAUNCHER_DIR` (see Settings). Also make sure the `2>&1 \| cat` part was not removed from the script (see "What `ignition -d` actually runs") |
| `Designer Launcher exited with code N` | The launcher failed: run the command from "What `ignition -d` actually runs" by hand inside the toolbox to see the error; also see the Troubleshooting section of the main setup guide |
| `Toolbox 'ignition-designer' does not exist` | Create it first (main setup guide, section 6) or set `IGNITION_TOOLBOX` |

---

## Removal

```bash
rm ~/.local/bin/ignition
rm ~/projects/kanoa-docker-template/ignition.sh
```
