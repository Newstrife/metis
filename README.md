# Metis

[![CI](https://github.com/chagel/metis/actions/workflows/ci.yml/badge.svg)](https://github.com/chagel/metis/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/chagel/metis/pulls)

**pi runs on your laptop. Metis runs pi for everyone you work with —
in a sandbox, on your stack, with your provider.**

An open, self-hostable agent platform built on **pi**, a fast, open
agent harness. Streaming web chat, multi-user from day one, the agent
sandboxed by default. Coding is one capability, not the boundary.

- **[`VISION.md`](VISION.md)** — what Metis is, the rules we hold to,
  what we won't build.
- **[`PLAN.md`](PLAN.md)** — current status, roadmap, and open
  questions.
- **[`docs/`](docs/)** — architecture (tenancy, connectors, session
  persistence).

## Stack

- **Rails 8.1**, Ruby 4.0.5, PostgreSQL
- **pi** agent harness, driven via the [`pi-agent-rb`](https://github.com/chagel/pi-agent-rb) gem
- **Any LLM provider [pi supports](https://pi.dev/docs/latest/providers)** — Anthropic, OpenAI, Google, DeepSeek, xAI, Groq, Cerebras, Mistral, OpenRouter, Together, Fireworks, Hugging Face, and more — chosen per conversation
- **Hotwire** (Turbo + Stimulus, importmap) and **Tailwind** for the live chat UI
- **Devise** for authentication
- **Solid Queue / Cache / Cable** for jobs, cache, and Action Cable

## Prerequisites

- Ruby 4.0.5 — see `.ruby-version` (a version manager such as `mise` is recommended)
- PostgreSQL
- **pi** on your `PATH` for the `local` runtime —
  `npm install -g @earendil-works/pi-coding-agent`.

Optional, only if you use the matching runtime:

- Docker — for the `docker` runtime.
- An [E2B](https://e2b.dev) account — for the `e2b` runtime.

## Setup

```sh
bin/setup        # install dependencies and prepare the database
```

`bin/setup` also installs the **MCP connector bridge**
([`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter)) into
your local pi. The `docker` image and `e2b` template bake the same
bridge in at build time, so every runtime has it.

Metis encrypts `Message#content` and `Message#reasoning` with Active
Record Encryption — the encryption keys must be present in Rails
credentials for every environment, test included.

## Running

```sh
bin/dev          # Puma + Tailwind watch via foreman → http://localhost:3000
```

`bin/dev` loads a `.env` file from the project root (via foreman).

## Configuration

pi's runtime and credentials are configured through the environment
(`.env` in development):

| Variable | Purpose |
|---|---|
| `METIS_AGENT_RUNTIME` | `local` (default), `docker`, or `e2b` |
| `METIS_AGENT_PROVIDER` / `METIS_AGENT_MODEL` | default LLM provider/model for pi |
| Provider API keys — `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, … | see [Providers](#providers) |
| `METIS_DOCKER_IMAGE` | image for the `docker` runtime (default `metis-pi`) |
| `E2B_API_KEY` / `METIS_E2B_TEMPLATE` | required by the `e2b` runtime |

### Runtimes

- **`local`** — pi runs as a local subprocess. Fast, but **not an
  isolation boundary**: pi has shell access to the host. For
  single-operator / development use.
- **`docker`** — pi runs in a Docker container: namespace isolation,
  dropped capabilities, and resource limits, on a shared kernel.
  Self-hosted, needs a Docker daemon. Build the image once:

  ```sh
  rake "docker:image[metis-pi]"
  ```
- **`e2b`** — pi runs inside an isolated [E2B](https://e2b.dev) microVM.
  Build the sandbox template once:

  ```sh
  rake "e2b:template[metis-pi]"
  ```

### Providers

Metis runs on **your provider** — there is no Metis-hosted inference.
Anything [pi supports](https://pi.dev/docs/latest/providers) works
here, picked per conversation in the new-chat composer. Set whichever
keys you want available; conversations only see providers your
deployment is keyed for.

| Env var | Provider |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI (GPT) |
| `GEMINI_API_KEY` | Google (Gemini) |
| `DEEPSEEK_API_KEY` | DeepSeek |
| `XAI_API_KEY` | xAI (Grok) |
| `GROQ_API_KEY` | Groq |
| `CEREBRAS_API_KEY` | Cerebras |
| `MISTRAL_API_KEY` | Mistral |
| `OPENROUTER_API_KEY` | OpenRouter |
| `TOGETHER_API_KEY` | Together AI |
| `FIREWORKS_API_KEY` | Fireworks |
| `HF_TOKEN` | Hugging Face |

Variable names mirror pi's own conventions so the same env that runs
pi locally works here. The new-chat composer's curated dropdown lives
in `app/services/agent/catalog.rb` — add provider/model entries there
to surface them in the UI.

## Testing

```sh
bin/rails test   # full Minitest suite
bin/rubocop      # lint (rubocop-rails-omakase)
bin/ci           # rubocop, security scans, and tests
```

## Architecture

One turn flows from the browser down to pi and streams back up, live:

```
   Browser · Hotwire chat UI
      │  new message                  ▲  Turbo Stream
      ▼                               │  (live text, tool calls)
   MessagesController                 ChatBroadcaster
      │  persist + enqueue            ▲  UiEvent
      ▼                               │
   ChatJob · Solid Queue ─────────────┘
      │  one turn — stream UiEvents, persist the final message
      ▼
   Agent service layer  (app/services/agent/)
      ├─ Adapters::Pi   the agent — drives pi, native events → UiEvent
      └─ Runtime        where pi runs — Local · Docker · E2b
      │
      ▼  pi-agent-rb · JSONL over stdio
   pi --mode rpc · the agent harness — LLM loop, tools, extensions

   Persistence
      ├─ PostgreSQL       conversations & messages
      └─ Workspace fs     Docker bind mount · E2b pause/resume · Local host
```

The core is the **Agent service layer** (`app/services/agent/`): an
*adapter* drives pi and translates its native event stream into a
canonical `UiEvent` vocabulary, and a *runtime* decides where pi runs.
See [`CLAUDE.md`](CLAUDE.md) for a fuller tour.
