# Metis

**Metis is an open-source, self-hostable agent platform for individuals
and teams.**

It runs **pi** — a fast, open agent harness — behind a live, streaming
web chat UI. pi ships with coding tools, but its extensions and skills
make Metis a general-purpose personal agent: coding is one capability,
not the boundary. The agent runs in a sandbox, so it is safe to let it
run untrusted code, and the LLM provider is yours to choose — Metis is
not provider-locked.

Metis is web-first and multi-user by design. Personal productivity is
the start, not the end: the goal is a platform where people build their
own tools and share them — across their devices, and with their teams.

See [`PLAN.md`](PLAN.md) for direction and roadmap.

## Stack

- **Rails 8.1**, Ruby 4.0.5, PostgreSQL
- **pi** agent harness, driven via the `pi-agent-rb` gem
- **Hotwire** (Turbo + Stimulus, importmap) and **Tailwind** for the live chat UI
- **Devise** for authentication
- **Solid Queue / Cache / Cable** for jobs, cache, and Action Cable

## Prerequisites

- Ruby 4.0.5 — see `.ruby-version` (a version manager such as `mise` is recommended)
- PostgreSQL
- **`pi-agent-rb`** checked out as a sibling directory at `../pi-agent-rb`.
  The `Gemfile` references it as a local path gem, so `bundle` fails without it.
- **pi** on your `PATH` for the `local` runtime —
  `npm install -g @earendil-works/pi-coding-agent`.
- Docker — only for the `docker` runtime.
- An [E2B](https://e2b.dev) account — only for the `e2b` runtime.

## Setup

```sh
bin/setup        # install dependencies and prepare the database
```

`bin/setup` also installs the **MCP connector bridge**
([`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter)) into
your local pi. The `docker` image and `e2b` template bake the same
bridge in at build time, so every runtime has it.

Metis encrypts `Message#content`, `Message#reasoning`, and `ApiKey#key`
with Active Record Encryption — the encryption keys must be present in
Rails credentials for every environment, test included.

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
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GOOGLE_API_KEY` | provider API keys |
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
      └─ Active Storage   Agent::SessionArchive · durable pi session
```

The core is the **Agent service layer** (`app/services/agent/`): an
*adapter* drives pi and translates its native event stream into a
canonical `UiEvent` vocabulary, and a *runtime* decides where pi runs.
See [`CLAUDE.md`](CLAUDE.md) for a fuller tour.
