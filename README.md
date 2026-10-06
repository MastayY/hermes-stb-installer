# hermes-stb-installer

Auto-deploy [Hermes Agent](https://github.com/NousResearch/hermes-agent) +
[9Router](https://github.com/decolua/9router) on homelab STB hardware
(Android TV boxes flashed with Armbian/Debian, aarch64, typically 1-2GB RAM).

`curl | bash` that doesn't assume you know container networking, and is
built specifically not to repeat a UFW/Docker lockout this project's
history already ran into once — see
[docs/RESEARCH_NOTES.md](docs/RESEARCH_NOTES.md) for the full reasoning
and what's been verified vs. still needs testing on real hardware.

## What you get

- **Hermes Agent** — chat with your own AI assistant over Telegram (no
  ports need to be opened; it uses outbound long-polling)
- **9Router** — self-hosted BYOK gateway in front of Hermes, so you bring
  your own provider (any built-in provider 9Router supports, or any custom
  OpenAI/Anthropic-compatible endpoint — see `docs/PROVIDERS.md`), with
  optional automatic fallback across several models
- Runs on **Podman rootless by default** (daemonless, and its networking
  doesn't touch host iptables/UFW at all 
- Least-privilege secrets: each container only receives the variables it needs, and Hermes talks to 9router with its own auto-generated API key
- Automatic swapfile on low-RAM devices, log rotation, resource limits per
  container, and a "lite" mode that disables Hermes's heaviest tools
  (browser automation, vision, image/video gen) for weaker hardware

## Requirements

- An STB (or any Linux box) running a Debian-family OS (Armbian, Debian,
  Ubuntu), aarch64 or x86_64
- Root/sudo access
- At least one AI provider you can connect in the 9Router dashboard —
  built-in (NVIDIA NIM, Cloudflare Workers AI, BytePlus, OpenAI, and many
  more) or a custom OpenAI/Anthropic-compatible endpoint. See
  `docs/PROVIDERS.md` — you connect it there first, then list the
  resulting model id in `.env`.
- A Telegram bot token from [@BotFather](https://t.me/BotFather)

## Quick start

```sh
git clone https://github.com/MastayY/hermes-stb-installer
cd hermes-stb-installer
cp .env.example .env
nano .env   # fill in your Telegram bot token for now
sudo ./install.sh
```

Then connect a provider in the 9Router dashboard (`docs/PROVIDERS.md`), add
its model id to `NINE_ROUTER_MODELS` in `.env`, and re-run `sudo
./install.sh` — it's idempotent, safe to run again.

Prefer not to pipe a script straight into bash? Reasonable instinct for a
homelab — clone, read `install.sh` and the `lib/` scripts it sources, then
run it as above once you're satisfied.

## Options

```
./install.sh [options]

  --runtime=podman|docker   Container runtime (default: podman)
  --no-swap                 Skip automatic swapfile creation
  --with-proxy=<domain>     Set up Caddy reverse proxy for the 9router
                             dashboard at <domain> (off by default)
  -h, --help                Show help
```

By default, nothing is exposed beyond your LAN: the 9router dashboard binds
to all interfaces on port `20128` but isn't proxied or TLS'd, and Telegram
uses outbound polling so no inbound port is needed for chat at all. Only
reach for `--with-proxy` if you specifically want the dashboard reachable
from outside your network — and change `INITIAL_PASSWORD` in `.env` from
its default before you do.

## After install

- Message your Telegram bot directly — that's the main interface
- Dashboard: `http://<device-ip>:20128/dashboard` (from your LAN, or over
  an SSH tunnel: `ssh -L 20128:localhost:20128 user@device-ip`)
- Logs: `podman logs -f hermes` / `podman logs -f 9router` (or `docker`,
  matching whichever runtime you chose)
- Change the model(s): edit `NINE_ROUTER_MODELS` in `.env` (see
  `docs/PROVIDERS.md` for the id format) and re-run `sudo ./install.sh`,
  or change it directly in the 9router dashboard

## Checking Service Logs
For Podman:
```bash
podman logs -f 9router
podman logs -f hermes
```

For Docker:
```bash
docker logs -f 9router
docker logs -f hermes

## Updating

```sh
sudo ./update.sh
```

Pulls new images and recreates containers. Backs up `.env` and `data/` to
`backups/<timestamp>/` first. Does not touch your configuration.

## Uninstalling

```sh
sudo ./uninstall.sh
```

Stops and removes containers, reverts the UFW rule (if you used the Docker
runtime) or the podman-restart service (if Podman), and asks before
touching your data or swapfile.

## Repository layout

```
install.sh / uninstall.sh / update.sh
lib/            detect, swap, runtime selection, podman/docker setup,
                9router combo auto-setup, health checks
compose/        docker-compose.yml (+ optional proxy override)
config/         Hermes config.yaml template, Caddyfile template
data/           created at install time — SQLite DB, Hermes memory, etc.
docs/           PROVIDERS.md, COMPATIBILITY.md, TROUBLESHOOTING.md
```

## Contributing compatibility reports

Tried this on a specific STB model? Please add a row to
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) via PR — device, RAM,
runtime used, and how it went. This project targets hardware that's
inherently varied (STB kernels are frequently stripped-down community
builds), so real reports matter more than any spec sheet.

## License

MIT (this installer). Hermes Agent and 9Router are separate MIT-licensed
projects — see [LICENSE](LICENSE) for details.
