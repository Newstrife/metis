---
name: gws-gmail
description: "Gmail: send, read, reply, forward, triage, and watch email."
metadata:
  version: 0.22.5
  openclaw:
    category: "productivity"
    requires:
      bins:
        - gws
    cliHelp: "gws gmail --help"
---

# gmail (v1)

> **PREREQUISITE:** Read `../gws-shared/SKILL.md` for auth, global flags, and security rules.

```bash
gws gmail <resource> <method> [flags]
```

Helper commands (`+name`) wrap the raw API for common tasks:

| Command | Purpose |
|---------|---------|
| [`+triage`](#triage) | Unread inbox summary (read-only) |
| [`+read`](#read) | Read one message's body or headers |
| [`+send`](#send) | Send a new email |
| [`+reply`](#reply) | Reply to a message (threaded) |
| [`+reply-all`](#reply-all) | Reply-all to a message (threaded) |
| [`+forward`](#forward) | Forward a message to new recipients |
| [`+watch`](#watch) | Stream new mail as NDJSON via Pub/Sub |

---

## +triage

Show unread inbox summary (sender, subject, date). Read-only — never modifies the mailbox.

```bash
gws gmail +triage
```

| Flag | Default | Description |
|------|---------|-------------|
| `--max` | 20 | Maximum messages to show |
| `--query` | `is:unread` | Gmail search query |
| `--labels` | — | Include label names in output |

```bash
gws gmail +triage
gws gmail +triage --max 5 --query 'from:boss'
gws gmail +triage --format json | jq '.[].subject'
```

## +read

Read a message and extract its body or headers.

```bash
gws gmail +read --id <ID>
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--id` | ✓ | — | Gmail message ID |
| `--headers` | — | — | Include From/To/Subject/Date |
| `--format` | — | text | `text` or `json` |
| `--html` | — | — | Return HTML body instead of plain text |
| `--dry-run` | — | — | Show the request without executing |

```bash
gws gmail +read --id 18f1a2b3c4d
gws gmail +read --id 18f1a2b3c4d --headers
gws gmail +read --id 18f1a2b3c4d --format json | jq '.body'
```

Converts HTML-only messages to plain text automatically; handles multipart/alternative and base64.

## +send

> [!CAUTION]
> **Write** command — confirm with the user before executing.

```bash
gws gmail +send --to <EMAILS> --subject <SUBJECT> --body <TEXT>
```

| Flag | Required | Description |
|------|----------|-------------|
| `--to` | ✓ | Recipient(s), comma-separated |
| `--subject` | ✓ | Subject line |
| `--body` | ✓ | Plain text, or HTML with `--html` |
| `--from` | — | Send-as/alias address |
| `--cc` / `--bcc` | — | Additional recipients |
| `--attach` (`-a`) | — | File path; repeat for multiple. 25MB total |
| `--html` | — | Treat `--body` as HTML (fragment tags only) |
| `--draft` | — | Save as draft instead of sending |
| `--dry-run` | — | Show the request without executing |

```bash
gws gmail +send --to alice@example.com --subject 'Hello' --body 'Hi Alice!'
gws gmail +send --to alice@example.com --subject 'Report' --body 'See attached' -a report.pdf
gws gmail +send --to alice@example.com --subject 'Hi' --body '<b>Bold</b>' --html
gws gmail +send --to alice@example.com --subject 'Hi' --body 'Draft' --draft
```

Handles RFC 5322 formatting, MIME encoding, and base64 automatically. With `--html`, use fragment tags (`<p>`, `<b>`, `<a>`) — no `<html>`/`<body>` wrapper.

## +reply

> [!CAUTION]
> **Write** command — confirm with the user before executing.

Reply to a message; threading is handled automatically (In-Reply-To, References, threadId).

```bash
gws gmail +reply --message-id <ID> --body <TEXT>
```

Same flags as `+send`, plus `--message-id` (required) and `--to` to add extra recipients to the To field. The original message is quoted in the reply body. For reply-all, use `+reply-all` instead.

```bash
gws gmail +reply --message-id 18f1a2b3c4d --body 'Thanks, got it!'
gws gmail +reply --message-id 18f1a2b3c4d --body 'Looping in Carol' --cc carol@example.com
gws gmail +reply --message-id 18f1a2b3c4d --body '<b>Bold reply</b>' --html
```

## +reply-all

> [!CAUTION]
> **Write** command — confirm with the user before executing.

Reply to the sender and all original To/CC recipients.

```bash
gws gmail +reply-all --message-id <ID> --body <TEXT>
```

Same flags as `+reply`, plus `--remove <emails>` to exclude specific recipients from the outgoing reply (including the sender). Fails if no To recipient remains after `--remove` + `--to` adjustments.

```bash
gws gmail +reply-all --message-id 18f1a2b3c4d --body 'Sounds good!'
gws gmail +reply-all --message-id 18f1a2b3c4d --body 'Updated' --remove bob@example.com
```

## +forward

> [!CAUTION]
> **Write** command — confirm with the user before executing.

Forward a message to new recipients. Includes original sender, date, subject, and (by default) attachments.

```bash
gws gmail +forward --message-id <ID> --to <EMAILS>
```

| Flag | Required | Description |
|------|----------|-------------|
| `--message-id` | ✓ | Message to forward |
| `--to` | ✓ | New recipient(s) |
| `--body` | — | Note above the forwarded message |
| `--no-original-attachments` | — | Drop original attachments |

Plus the standard `--from`, `--cc`, `--bcc`, `--attach`, `--html`, `--draft`, `--dry-run`.

```bash
gws gmail +forward --message-id 18f1a2b3c4d --to dave@example.com
gws gmail +forward --message-id 18f1a2b3c4d --to dave@example.com --body 'FYI'
gws gmail +forward --message-id 18f1a2b3c4d --to dave@example.com --no-original-attachments
```

Original + user attachments capped at 25 MB combined.

## +watch

Stream new emails as NDJSON via Pub/Sub. Gmail watch expires after 7 days — re-run to renew.

```bash
gws gmail +watch --project <GCP-PROJECT>
```

| Flag | Default | Description |
|------|---------|-------------|
| `--project` | — | GCP project ID for Pub/Sub |
| `--subscription` | — | Existing subscription (skip setup) |
| `--topic` | — | Existing topic with Gmail push grant |
| `--label-ids` | — | Comma-separated label filter (e.g. `INBOX,UNREAD`) |
| `--max-messages` | 10 | Max per pull batch |
| `--poll-interval` | 5 | Seconds between pulls |
| `--msg-format` | full | `full`, `metadata`, `minimal`, `raw` |
| `--once` | — | Pull once and exit |
| `--cleanup` | — | Delete created Pub/Sub resources on exit |
| `--output-dir` | — | Write each message to a JSON file in this dir |

```bash
gws gmail +watch --project my-gcp-project
gws gmail +watch --project my-project --label-ids INBOX --once
gws gmail +watch --subscription projects/p/subscriptions/my-sub
```

Press Ctrl-C to stop. Without `--cleanup`, Pub/Sub resources persist for reconnection.

---

## Raw API resources

For anything outside the helper commands above, drop down to the API:

```bash
gws gmail <resource> <method> [--params '{...}'] [--json '{...}']
```

Resources: `users` (getProfile, stop, watch), `users.drafts`, `users.history`, `users.labels`, `users.messages`, `users.settings`, `users.threads`.

Discover before calling:

```bash
gws gmail --help                       # browse resources and methods
gws schema gmail.<resource>.<method>   # required params, types, defaults
```
