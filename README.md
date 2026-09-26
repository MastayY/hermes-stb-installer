# Hermes Agent and 9Router STB Homelab Installer

An automated deployment tool designed to run Nous Research Hermes Agent and 9Router on resource-constrained Linux systems and repurposed Android TV boxes (STBs) running Armbian or Debian.

---

## Overview

Running AI assistants and multi-provider fallback proxies on hardware with 1 GB to 2 GB of RAM presents specific constraints. Standard container setups can quickly exhaust available memory or trigger firewall conflicts.

This installer provides:
- Default rootless Podman execution to eliminate daemon memory overhead.
- Automatic memory detection and proportional swapfile allocation.
- A Lite mode for Hermes Agent that disables heavy browser automation and vision tools.
- Explicit container memory limits to prevent out-of-memory kernel panics.
- Automated 9Router provider and fallback combo provisioning.
- Optional Caddy TLS reverse proxy with basic authentication.
- Idempotent execution and complete, non-destructive uninstall scripts.

---

## Hardware and System Requirements

| Specification | Minimum | Recommended | Notes |
| :--- | :--- | :--- | :--- |
| Architecture | 64-bit ARM (aarch64) or x86_64 | aarch64 | 32-bit (armv7l) is unsupported by upstream images |
| RAM | 1 GB physical RAM | 2 GB or more | Automated swap allocation activates for <= 2 GB |
| Storage | 4 GB free disk space | 8 GB or more | Required for base images and swapfile |
| Operating System | Debian 11/12, Ubuntu 22.04/24.04, Armbian | Armbian (Debian Bookworm base) | Kernel must support cgroups and user namespaces |

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/example/hermes-stb-installer.git
cd hermes-stb-installer
```

### 2. Configure Environment Secrets

Copy the example environment file and edit your credentials:

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Set your Telegram Bot token and provider API keys:
- `TELEGRAM_BOT_TOKEN`: Token obtained from [@BotFather](https://t.me/botfather).
- `TELEGRAM_ALLOWED_USERS`: Comma-separated numerical Telegram user IDs.
- Provider keys (e.g. `OPENROUTER_API_KEY`, `DEEPSEEK_API_KEY`, `GROQ_API_KEY`).

### 3. Run the Installer

For standard installation (Podman rootless by default):

```bash
./install.sh
```

For devices with 1 GB RAM:

```bash
./install.sh --lite
```

---

## CLI Options

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--runtime=podman\|docker` | Selects container runtime | `podman` |
| `--lite` | Activates low-RAM profile (disables Chromium and vision tools) | Auto-detected if RAM <= 2 GB |
| `--with-proxy` | Deploys Caddy reverse proxy on ports 80/443 with TLS and basicauth | Disabled |
| `--no-swap` | Skips automatic swapfile allocation | Disabled |
| `--non-interactive` | Runs without prompting for interactive inputs | Disabled |
| `--help`, `-h` | Shows usage documentation | |

---

## Architecture

```
+---------------------------------------------------------+
|                  STB Host (Armbian aarch64)              |
|                                                         |
|  +--------------------+        +---------------------+  |
|  |    Hermes Agent    |------->|       9Router       |  |
|  |  (Gateway Service) |        |  (Port 20128, LAN)  |  |
|  +---------+----------+        +----------+----------+  |
|            |                              |             |
|            | Outbound                     | Outbound    |
|            v                              v             |
|       Telegram API                 LLM Providers        |
|      (Long-polling)            (OpenRouter, DeepSeek)   |
+---------------------------------------------------------+
```

### Network Isolation
- Hermes Agent connects to 9Router over an internal container bridge network.
- 9Router dashboard binds to `127.0.0.1:20128` by default to avoid unauthenticated exposure on local area networks.
- Telegram communication operates via outbound HTTPS long-polling, requiring no inbound port forwarding.

---

## Accessing the 9Router Dashboard

Because 9Router is bound to localhost for security, access the web dashboard from your desktop using an SSH tunnel:

```bash
ssh -L 20128:127.0.0.1:20128 user@<STB_IP_ADDRESS>
```

Then navigate to:
```
http://localhost:20128/dashboard
```

---

## Management and Maintenance

### Updating Images
To pull the latest container images and restart services without modifying configuration or databases:

```bash
./update.sh
```

If running the low-RAM profile:

```bash
./update.sh --lite
```

### Checking Service Logs
For Podman:
```bash
podman logs -f 9router
podman logs -f hermes-agent
```

For Docker:
```bash
docker logs -f 9router
docker logs -f hermes-agent
```

### Uninstallation
To cleanly tear down containers and reset firewall rules:

```bash
./uninstall.sh
```

To also delete persistent model databases and configuration files:

```bash
./uninstall.sh --purge-data --remove-swap
```

---

## Security Implementation

1. **Rootless by Default**: Podman executes within an unprivileged user namespace. System iptables rules are untouched.
2. **Docker Firewall Hardening**: When Docker fallback is selected (`--runtime=docker`), the installer injects a `DOCKER-USER` chain filter into `/etc/ufw/after.rules` to prevent Docker from bypassing existing UFW firewall policies.
3. **Log Rotation**: Docker daemon configuration is capped with `max-size: 10m` and `max-file: 3` to protect eMMC and microSD storage from disk exhaustion.
4. **Credential Isolation**: The generated `.env` file is set to mode `0600`. Tokens are passed into container processes via environment variables and never logged to stdout or files.

---

## License

This project is released under the [MIT License](LICENSE).
