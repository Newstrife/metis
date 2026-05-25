# Metis Model Details

The full domain is small on purpose — Metis is a chat UI in front of pi, not its own agent platform.

## User

Devise + OmniAuth. Identity-first lookup; email is fallback only when
the provider's address is verified (anchored noreply pattern check
prevents pseudo-emails from matching real ones).

```ruby
devise :database_authenticatable, :registerable, :recoverable,
       :rememberable, :validatable, :omniauthable,
       omniauth_providers: %i[github google_oauth2 linear]

has_many :memberships, dependent: :destroy
has_many :teams, through: :memberships
has_many :conversations, dependent: :destroy
has_many :connector_credentials, dependent: :destroy
has_many :identities, dependent: :destroy        # (provider, uid) lookup keys
has_many :oauth_grants, dependent: :destroy      # token + scope set per provider

after_create :create_personal_team               # team-of-one at signup

def personal_team = teams.find_by(personal: true)
```

`User.from_omniauth(auth)`:
- Looks up `Identity.find_by(provider:, uid:)` first (durable handle).
- Falls back to `find_or_initialize_by(email:)` only when the address
  is verified per `email_verified_for?(auth)` (GitHub: always true on
  `user:email` scope; Google: explicit `email_verified == true`).
- Unverified → `noreply_email(auth)` synthesizes `<uid>+<handle>@<provider>.users.noreply.metis`.
- Wraps the create in a transaction with a one-shot retry: on
  `RecordNotUnique`, the loser re-reads `Identity` and finds the
  winner. Handles the concurrent-first-sign-in race.
- `backfill_real_email` promotes a placeholder to a real email when
  the provider later starts returning one (never the reverse).

## Team

The single tenancy unit (`docs/tenancy.md`). Every ownable resource
belongs to a team.

```ruby
has_many :memberships, dependent: :destroy
has_many :members, through: :memberships, source: :user
has_many :conversations, dependent: :destroy
has_many :connectors, dependent: :destroy

# A `personal` boolean marks the team-of-one created at signup.
```

## Membership

Joins user → team with a role. No polymorphic `owner`.

```ruby
belongs_to :user
belongs_to :team

enum :role, { member: 0, admin: 1, owner: 2 }
validates :user_id, uniqueness: { scope: :team_id }
```

## Identity

A `(provider, uid)` pair — the durable handle the OmniAuth callback
uses to recognise an existing user. **Not** the same as `OauthGrant`
(Identity stores the omniauth strategy name like `google_oauth2`;
OauthGrant stores the canonical provider like `google` —
`OauthBroker.normalize_provider` bridges them).

```ruby
belongs_to :user
validates :provider, presence: true
validates :uid, presence: true, uniqueness: { scope: :provider }
```

## OauthGrant

**The single source of truth for OAuth tokens.** One per
`(user, provider)`, holding access + refresh tokens and the union of
every scope ever granted across all connectors wired to that
provider. `ConnectorCredential` rows for OAuth-shaped connectors are
*presence markers* — the tokens live here.

```ruby
belongs_to :user

encrypts :access_token
encrypts :refresh_token

validates :provider, uniqueness: { scope: :user_id },
                     inclusion: { in: OauthBroker::PROVIDERS }

REFRESH_LEEWAY      = 60.seconds   # treat tokens this close to expiry as stale
DEFAULT_EXPIRES_IN  = 1.hour       # fallback when neither response nor prior grant has expiry

def fresh?  # expires_at present AND > REFRESH_LEEWAY in the future
def scope_set       # array of granted scopes (space- or comma-separated input)
def covers?(required)  # every scope in `required` is in scope_set
def absorb!(response, at: Time.current)
  # Replaces (not unions) scopes when the response carries them —
  # otherwise covers? returns true for a scope the user just revoked
  # on the consent screen. Preserves prior refresh_token when omitted
  # (Google omits on refresh). Falls back to DEFAULT_EXPIRES_IN if
  # neither response nor prior grant has expires_at — without this
  # legacy backfill rows refresh on every chat turn.
def remove_scopes!(scopes_to_remove)
  # Drops scopes locally when a connector is disconnected. Does NOT
  # touch the grant at the provider; revocation is handled separately
  # when the last OAuth connector for a provider is disconnected.
```

## Connector

One configured MCP server, owned by a team. Becomes a `mcpServers`
entry in the per-turn `.mcp.json` rendered by `Agent::McpConfig`.

```ruby
belongs_to :team
has_many :connector_credentials, dependent: :destroy

# stdio — a `command` server entry; http — a `url` server entry
enum :transport, { stdio: 0, http: 1 }

validates :name, format: { with: /\A[a-z0-9][a-z0-9_-]*\z/i },
                 uniqueness: { scope: :team_id }
validate :definition_matches_transport  # stdio needs "command", http needs "url"

def credential_for(user)
  # The member's own credential if set, else the team's shared one.
  connector_credentials.find_by(user: user) || connector_credentials.find_by(user: nil)
end

def catalog_app
  # The ConnectorCatalog::App this connector was created from, or
  # nil for a custom (off-catalog) connector.
  ConnectorCatalog.find(catalog_key)
end
```

## ConnectorCredential

A per-member presence marker on a team's Connector. For **token-auth**
connectors, the secret IS here (in the `headers` envelope on the
encrypted `credentials` column). For **OAuth-shaped** connectors, the
token lives in `OauthGrant` — this row just records "this member
wired this connector up".

A row with `user_id = nil` is the team's shared credential (a service
account, only meaningful for token-auth).

```ruby
belongs_to :connector
belongs_to :user, optional: true

encrypts :credentials
validates :user_id, uniqueness: { scope: :connector_id }

def credential_map
  # The header bag ("Authorization" => "Bearer xyz") to merge into
  # the connector's .mcp.json entry. Token-auth stores these
  # directly; OAuth returns {} — runtime projects the live token
  # through the catalog's credential format.
end

def oauth_grant
  # The user's grant for the connector's provider, or nil. Same
  # grant covers every connector wired to the same provider.
end

def oauth_ready?
  # OAuth-shaped + token present + scopes cover the catalog's
  # required scopes. For GitHub (scope_check_meaningful? == false),
  # token presence is the only gate — App install permissions are
  # the real authorization.
end
```

## Conversation

```ruby
belongs_to :user
belongs_to :team
has_many :messages, dependent: :destroy

before_validation :default_team, on: :create  # defaults to user.personal_team
before_destroy :kill_paused_e2b_sandbox       # E2B doesn't auto-clean

scope :recent, -> { order(updated_at: :desc) }

# Persisted per-turn:
#   settings       — provider/model picked in the composer (jsonb)
#   backend_session_id — pi's --session-dir handle for --continue
#   agent_model    — {id, name, provider} pi actually resolved
#   runtime_state  — { "runtime" => "local|docker|e2b", … }
#   context_usage  — { tokens, contextWindow, percent } per latest turn
#   e2b_sandbox_id — for Runtime::E2b resume across turns
#   cancel_requested_at — set by #request_cancel!, polled by ChatJob

def model_label    # agent_model["name"] || settings["model"]
def runtime_label  # runtime_state["runtime"]
def turn_in_progress?
  # Returns true while an assistant message is :pending or :streaming;
  # MessagesController uses this to refuse a concurrent turn (also
  # backed by a partial unique index that catches the TOCTOU race).
def request_cancel!  # stamps cancel_requested_at; ChatJob polls every 15 events

def uploaded_files
  # Every file attached across the conversation — projected into
  # workspace/uploads/ each turn (durable input, not session state).
  messages.with_attached_files.flat_map { |m| m.files.attachments }
end
```

## Message

```ruby
enum :role,             { user: 0, assistant: 1, tool: 2, system: 3 }
enum :streaming_status, { pending: 0, streaming: 1, done: 2, errored: 3, canceled: 4 }

belongs_to :conversation
has_many_attached :images   # sent inline via pi's vision protocol
has_many_attached :files    # staged into workspace/uploads/

encrypts :content
encrypts :reasoning

ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp]
ALLOWED_FILE_TYPES  = %w[application/pdf text/plain text/csv text/markdown
                         application/json application/xml text/xml]
MAX_UPLOAD_SIZE = 10.megabytes

# Per-turn token columns (deltas vs prior turns, computed in ChatJob):
#   input_tokens, output_tokens, cache_read_tokens
# tool_calls : jsonb array — one entry per tool call, accumulated across
#              started/progress/finished events.

def duration  # finished_at - started_at, or nil
```

`ChatJob` scrubs `\x00` from every persisted string/array/hash —
PostgreSQL refuses U+0000 in text/jsonb, and pi occasionally emits one
inside a tool call payload (binary leak, malformed file read).
