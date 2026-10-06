# Connecting a provider

This installer doesn't assume which AI provider(s) you use — you connect
them yourself in the 9Router dashboard, then list the resulting model id(s)
in `.env` (`NINE_ROUTER_MODELS`). This page is a short walkthrough of both
ways to do that.

Open `http://<device-ip>:20128/dashboard` → **Providers**.

## Option A — a built-in provider

9Router ships with a long list of built-in providers (NVIDIA NIM, Cloudflare
Workers AI, BytePlus, OpenAI, Anthropic, OpenRouter, and many more). Pick
yours from the list, paste your API key. Cloudflare additionally asks for
your **Account ID** (Cloudflare dashboard → right sidebar).

The resulting model id format is `<alias>/<model>`. The alias is usually
short and provider-specific — a few confirmed examples:

| Provider | Alias | Example model id |
|---|---|---|
| NVIDIA NIM | `nvidia` | `nvidia/deepseek-ai/deepseek-v4-flash` |
| Cloudflare Workers AI | `cf` | `cf/@cf/meta/llama-3.3-70b-instruct-fp8-fast` |
| BytePlus ModelArk | `bpm` | `bpm/glm-4-7-251222` |

For any other built-in provider, add it in the dashboard, then check
**Dashboard → Models** (or `GET /v1/models` with an API key) to see the
exact ids it exposes — provider aliases and available models both drift
over time, so that live list is more reliable than any list written here.

## Option B — a custom OpenAI/Anthropic-compatible endpoint

Anything not in the built-in list — a different cloud provider, your own
proxy, a self-hosted OpenAI-compatible server reachable from this device —
connects as a **custom provider**:

1. Dashboard → Providers → **"Add OpenAI Compatible"** (or **"Add Anthropic
   Compatible"** if it speaks Anthropic's API shape instead).
2. Fill in:
   - **Name** — anything, just a label.
   - **Prefix** — your choice, becomes the alias in model ids (e.g.
     `mycustom`). Keep it short, no slashes.
   - **Base URL** — the endpoint's base URL, e.g. `http://localhost:11434/v1`
     for a local Ollama, or whatever your provider gives you (should end in
     `/v1`).
   - **API Type** (OpenAI-compatible only) — Chat Completions or Responses
     API, whichever that endpoint implements.
3. Save, then paste the API key (leave blank if the endpoint needs none,
   e.g. a local server).

The resulting model id is `<your-prefix>/<whatever-model-id-that-endpoint-
uses>` — e.g. `mycustom/llama3.1:8b`. **Confirmed live: 9Router does not
validate or pre-register the model id for a custom provider** — whatever
string you put after the prefix is passed straight through to that
endpoint's own API at request time. So if your local Ollama's model is
called `llama3.1:8b`, the 9Router model id is just `mycustom/llama3.1:8b` —
no extra registration step needed.

## Then: tell the installer about it

Edit `.env`:

```sh
# one model, used directly:
NINE_ROUTER_MODELS=nvidia/deepseek-ai/deepseek-v4-flash

# or a few, for automatic fallback (first = highest priority):
NINE_ROUTER_MODELS=nvidia/deepseek-ai/deepseek-v4-flash,cf/@cf/meta/llama-3.3-70b-instruct-fp8-fast,mycustom/llama3.1:8b
```

Then run (or re-run — it's idempotent) `sudo ./install.sh`. With one model,
`lib/combo-setup.sh` points Hermes at it directly; with two or more, it
creates a 9Router combo (named by `NINE_ROUTER_COMBO_NAME`) and points
Hermes at that instead, so 9Router does the fallback between them.

If a listed model's prefix doesn't match any provider you've connected yet,
`install.sh` prints a warning (not a hard failure) naming the prefix it
couldn't find — connect that provider and re-run.

## An alternative worth knowing about: Hermes's own fallback

Separately from 9Router's combo fallback, **Hermes Agent has its own
native multi-provider fallback** (`fallback_providers:` in
`~/.hermes/config.yaml` inside the container, confirmed in
`website/docs/user-guide/features/fallback-providers.md`. Each entry can point at a different
provider/model, including a different custom `base_url` per entry — so it
could, for example, fall back to a completely different system (bypassing
9Router entirely) rather than another 9Router-routed model.

This installer does **not** use that mechanism by default — the tested,
default path is 9Router's own combo, since the whole point of running
9Router here is centralizing routing/fallback in one place rather than
duplicating it in each client. But if you want Hermes itself to fail over
outside of 9Router (e.g. to a local Ollama if 9Router itself becomes
unreachable), you can hand-edit `data/hermes/config.yaml` to add a
`fallback_providers:` list — see that doc page for the exact syntax. This
hasn't been tested end-to-end by this project; treat it as a documented
option, not a verified default.
