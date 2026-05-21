# Metis

A web chat UI for a coding agent. Metis puts a live, streaming chat
interface in front of **pi**, run either as a local process or inside an
isolated microVM.

Metis is built on a **single coding-agent foundation** by design — it is
an opinionated product, not a generic shell over swappable agent
backends.

## Stack

- **Rails 8.1**, Ruby 4.0.5, PostgreSQL
- **pi** coding agent, driven via the `pi-agent-rb` gem
- **Hotwire** (Turbo + Stimulus, importmap) and **Tailwind** for the live chat UI
- **Devise** for authentication
- **Solid Queue / Cache / Cable** for jobs, cache, and Action Cable

## Prerequisites

- Ruby 4.0.5 — see `.ruby-version` (a version manager such as `mise` is recommended)
- PostgreSQL
- **`pi-agent-rb`** checked out as a sibling directory at `../pi-agent-rb`.
  The `Gemfile` references it as a local path gem, so `bundle` fails without it.
- An [E2B](https://e2b.dev) account — only for the isolated runtime.

## Setup

```sh
bin/setup        # install dependencies and prepare the database
```

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
| `METIS_AGENT_RUNTIME` | `local` (default) or `e2b` |
| `METIS_AGENT_PROVIDER` / `METIS_AGENT_MODEL` | default LLM provider/model for pi |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GOOGLE_API_KEY` | provider API keys |
| `E2B_API_KEY` / `METIS_E2B_TEMPLATE` | required by the `e2b` runtime |

### Runtimes

- **`local`** — pi runs as a local subprocess. Fast, but **not an
  isolation boundary**: pi has shell access to the host. For
  single-operator / development use.
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

The core is the **Agent service layer** (`app/services/agent/`): an
*adapter* drives pi and translates its native event stream into a
canonical `UiEvent` vocabulary, and a *runtime* decides where pi runs.
See [`CLAUDE.md`](CLAUDE.md) for a fuller tour.
