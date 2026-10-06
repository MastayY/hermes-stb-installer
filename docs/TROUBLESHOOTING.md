# Troubleshooting

## `smoke_test_runtime` fails / `podman run --rm hello-world` fails

Usually means the kernel is missing something containers need. On
stripped-down Armbian builds for STB hardware this is common. Check:

```sh
cat /proc/cgroups          # need cpu, memory, pids controllers present with a non-zero "enabled" column
lsmod | grep overlay       # overlayfs module should be loaded (or built into the kernel)
```

If cgroups v1/v2 or overlayfs support is missing, you likely need a
different Armbian build for your device — check the compatibility matrix
(`docs/COMPATIBILITY.md`) for what others used successfully on the same
SoC.

## `install.sh` can't create the swapfile

- Check free storage: `df -h /` — STB storage (eMMC/SD) is often small,
  and the default swap sizing (up to 2GB) needs that much free space.
- Some SD cards / eMMC in read-only or heavily worn state will fail
  `dd`/`fallocate` — check `dmesg` for I/O errors.
- Run with `--no-swap` if you'd rather manage swap yourself.

## "no connected provider found for prefix 'xyz'" warning

`lib/combo-setup.sh` checks each model in `NINE_ROUTER_MODELS` against your
currently connected providers (built-in or custom) and warns — but doesn't
block — if a prefix isn't recognized. This almost always means the provider
for that model hasn't been connected in the dashboard yet. See
`docs/PROVIDERS.md`, connect it, then re-run `sudo ./install.sh` (safe to
run again). If you're confident the provider IS connected and still see
this, it's a detection gap in the check itself (it derives known prefixes
from `/v1/models` + `/api/provider-nodes`)
rather than a real problem; the model will still work once routed.

## 9router dashboard login fails from `lib/combo-setup.sh`

The script logs in via `POST /api/auth/login` using `INITIAL_PASSWORD`
from `.env`. If this fails:

1. Check 9router actually came up: `podman logs 9router` (or `docker logs`)
2. Confirm `INITIAL_PASSWORD` in `.env` matches what you expect — if
   `.env` was edited after the container's first boot, 9router may have
   already hashed a *different* password into its database on first run.
   In that case, either reset it via `9Router CLI → Settings → Reset
   Password to Default` (message shown by 9router's own login endpoint on
   failure) or log into the dashboard manually and update the combo/
   providers by hand.

## Hermes gets 401 "Missing API key" / "Invalid API key" from 9router

9router requires an API key on `/v1` by default. `install.sh` creates one
and stores it as `NINE_ROUTER_API_KEY` in `.env` and in
`data/hermes/config.yaml`. If it's missing or stale (e.g. you wiped 9router's
data but kept `.env`): clear `NINE_ROUTER_API_KEY=` in `.env`, then re-run
`sudo ./install.sh` (idempotent) to mint and apply a fresh one.

## "Invalid password ... attempts left before lockout"

9router locks the dashboard login after 5 wrong passwords. `combo-setup.sh`
tries exactly once. `INITIAL_PASSWORD` only applies on first boot — if you
later changed the password in the dashboard, the script can't log in; do the
provider/combo setup in the dashboard instead.

## Hermes can't reach 9router (`connection refused` in Hermes logs)

- Hermes uses `network_mode: host` and expects 9router at
  `http://localhost:20128/v1` (see `compose/docker-compose.yml`). Confirm
  9router is actually listening on that port: `curl localhost:20128/api/health`
  from the host itself.
- If you changed `PORT` in `.env` for 9router, update
  `config/hermes-config.yaml.template`'s `base_url` (and re-run install, or
  edit `data/hermes/config.yaml` directly) to match.

## Out-of-memory / containers getting killed

- Check actual usage: `free -h` and `podman stats` / `docker stats`.
- Confirm `HERMES_MODE=lite` is set in `.env` (disables browser automation,
  vision, image/video gen, TTS — the heaviest tool categories).
- Confirm swap is active: `swapon --show`. If it isn't and RAM is under
  2GB, re-run `install.sh` without `--no-swap`.
- The `mem_limit` values in `compose/docker-compose.yml` are estimates,
  not measured — if a container is being
  OOM-killed against its own limit rather than the host running out of
  memory, that limit may need raising for your workload, at the cost of
  less headroom for the other container.

## UFW rule didn't apply / `ufw reload` failed during install (Docker runtime only)

`lib/docker-fix.sh` backs up `/etc/ufw/after.rules` before editing it and
restores from that backup automatically if `ufw reload` fails. If you
still end up locked out of network access after a manual edit:

- You'll need physical/serial/recovery access to the device to fix this —
  there's no remote path around a bad firewall rule by design.
- Restore the most recent `*.pre-hermes9router.<timestamp>` backup file in
  `/etc/ufw/` and run `ufw reload`.
- Consider switching to the Podman runtime instead (`--runtime=podman`,
  the default), which doesn't touch UFW/iptables at all — this is the
  whole reason it's the default.

## Something else

Please open an issue with: device/SoC, `uname -a`, `free -h`, which
runtime, and the relevant `podman logs` / `docker logs` output. If you
find a fix, consider adding it here via PR.
