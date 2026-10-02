# Compatibility Matrix

Community-reported results. Please add a row via PR after trying this on
your device — real reports matter more than spec sheets here, since STB
kernels are frequently stripped-down community builds with unpredictable
cgroups/overlayfs support.

Fill in what you can; leave cells blank if unsure rather than guessing.

| Device | SoC / Arch | RAM | OS / Kernel | Runtime | Hermes mode | Status | Idle RAM usage | Notes |
|---|---|---|---|---|---|---|---|---|
| HG860p | Amlogic S905L3A / aarch64 | 2GB | Armbian (ophub/amlogic-s9xxx-armbian, bookworm) | podman | lite | _(not yet tested end-to-end)_ | | |

## Status legend

- ✅ **Works** — install completed, both services healthy, chat via
  Telegram confirmed working
- ⚠️ **Works with caveats** — up and running but needed manual
  intervention or has a known issue (link the issue/PR)
- ❌ **Fails** — describe where it failed (preflight, runtime smoke test,
  image pull, OOM, etc.) so others with similar hardware know what to
  expect

## What to include in a report

- Exact device/SoC (check `/proc/cpuinfo` or the box's marking)
- Output of `uname -m` and `free -h`
- Which Armbian/OS build (link if it's a community build)
- Runtime used (podman/docker) and whether the smoke test in
  `lib/runtime-select.sh` (`smoke_test_runtime`) passed
- `HERMES_MODE` used (lite/full)
- Actual idle memory usage after both containers are healthy — e.g.
  `free -h` before vs. after `docker compose up -d` / `podman compose up -d`
- Anything you had to change from the defaults to get it working
