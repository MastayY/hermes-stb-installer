# Troubleshooting and Diagnostic Guide

This guide covers resolution steps for common operational issues encountered when deploying Hermes Agent and 9Router on Armbian, Debian, and low-resource single-board computers.

---

## 1. Memory and Out-Of-Memory (OOM) Errors

### Symptoms
- `hermes-agent` or `9router` container exits abruptly with status code 137.
- `dmesg` contains `Out of memory: Killed process` or `oom-killer invoked`.

### Root Cause
- Physical RAM (1-2 GB) exhausted by unconstrained background processes or heavy browser automation tooling in Hermes Agent.

### Solutions
1. Ensure Lite mode is active. Lite mode caps container memory consumption and disables Chromium automation:
   ```bash
   ./update.sh --lite
   ```
2. Verify that a swapfile is active and at least 2 GB in size:
   ```bash
   swapon --show
   free -m
   ```
   If no swapfile is active, run the swap setup tool:
   ```bash
   ./lib/swap.sh 1024
   ```
3. Check `vm.swappiness` setting. STB devices benefit from moderate swappiness (e.g. 60):
   ```bash
   sysctl vm.swappiness
   sudo sysctl vm.swappiness=60
   ```

---

## 2. Podman Rootless Service Termination on Logout

### Symptoms
- Containers stop running immediately when the user disconnects their SSH session.

### Root Cause
- Systemd user linger is not enabled for the non-root user account.

### Solution
1. Verify user lingering status:
   ```bash
   loginctl show-user $(whoami) | grep Linger
   ```
2. If `Linger=no`, enable lingering:
   ```bash
   sudo loginctl enable-linger $(whoami)
   ```
3. Verify that the systemd user service is enabled:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now hermes-stb.service
   ```

---

## 3. Docker UFW Lockout or Firewall Bypass

### Symptoms
- External network connections fail or container services are exposed to the public internet despite UFW rules.

### Root Cause
- Docker daemon modifies `iptables` directly, bypassing standard UFW input chains.

### Solution
1. The installer automatically applies DOCKER-USER chain filters to `/etc/ufw/after.rules`. If missing, apply manually:
   ```bash
   ./lib/docker-fix.sh
   ```
2. Verify that 9Router binds strictly to `127.0.0.1` rather than `0.0.0.0`:
   ```bash
   ss -tulpn | grep 20128
   ```

---

## 4. Telegram Bot Initialization Failures

### Symptoms
- Hermes Agent logs show: `Connecting to Telegram...` indefinitely or `Invalid token`.

### Root Cause
- Incorrect `TELEGRAM_BOT_TOKEN` in `.env` or network blocking outbound HTTPS connections to `api.telegram.org`.

### Solution
1. Verify outbound connectivity to the Telegram Bot API:
   ```bash
   curl -I https://api.telegram.org
   ```
2. Check your `.env` configuration file permissions and token formatting:
   ```bash
   ls -l .env
   # Should be mode 600 (-rw-------)
   ```
3. Check Hermes Agent logs:
   ```bash
   podman logs --tail 50 hermes-agent
   # or
   docker logs --tail 50 hermes-agent
   ```

---

## 5. 9Router 404 or Model Fallback Failures

### Symptoms
- Chat client receives `404 Not Found` when requesting completions.
- `GET /v1/models` returns an empty array.

### Root Cause
- No providers or combos registered in 9Router SQLite database.

### Solution
1. Re-run the automated combo setup script:
   ```bash
   ./lib/combo-setup.sh
   ```
2. Check 9Router API endpoint locally:
   ```bash
   curl http://127.0.0.1:20128/v1/models
   ```
3. Connect via SSH tunnel to inspect the web dashboard directly:
   ```bash
   ssh -L 20128:127.0.0.1:20128 user@<STB_IP>
   ```
   Open `http://localhost:20128/dashboard` in your browser.
