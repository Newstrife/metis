---
name: gws-calendar
description: "Google Calendar: view upcoming events and create new ones."
metadata:
  version: 0.22.5
  openclaw:
    category: "productivity"
    requires:
      bins:
        - gws
    cliHelp: "gws calendar --help"
---

# calendar (v3)

> **PREREQUISITE:** Read `../gws-shared/SKILL.md` for auth, global flags, and security rules.

```bash
gws calendar <resource> <method> [flags]
```

Helper commands:

| Command | Purpose |
|---------|---------|
| [`+agenda`](#agenda) | Upcoming events across all calendars (read-only) |
| [`+insert`](#insert) | Create a new event |

---

## +agenda

Show upcoming events. Queries all calendars by default; uses your Google account timezone.

```bash
gws calendar +agenda
```

| Flag | Description |
|------|-------------|
| `--today` | Today's events |
| `--tomorrow` | Tomorrow's events |
| `--week` | This week's events |
| `--days <N>` | Next N days |
| `--calendar <NAME>` | Filter to one calendar (name or ID) |
| `--timezone <TZ>` | IANA override (e.g. `America/Denver`) |

```bash
gws calendar +agenda
gws calendar +agenda --today
gws calendar +agenda --week --format table
gws calendar +agenda --days 3 --calendar 'Work'
gws calendar +agenda --today --timezone America/New_York
```

## +insert

> [!CAUTION]
> **Write** command — confirm with the user before executing.

```bash
gws calendar +insert --summary <TEXT> --start <TIME> --end <TIME>
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--summary` | ✓ | — | Event title |
| `--start` | ✓ | — | RFC 3339 start (e.g. `2026-06-17T09:00:00-07:00`) |
| `--end` | ✓ | — | RFC 3339 end |
| `--calendar` | — | primary | Calendar ID |
| `--location` | — | — | Event location |
| `--description` | — | — | Event body |
| `--attendee` | — | — | Email; repeat for multiple |
| `--meet` | — | — | Attach a Google Meet link |

```bash
gws calendar +insert --summary 'Standup' --start '2026-06-17T09:00:00-07:00' --end '2026-06-17T09:30:00-07:00'
gws calendar +insert --summary 'Review' --start ... --end ... --attendee alice@example.com
gws calendar +insert --summary 'Sync' --start ... --end ... --meet
```

---

## Raw API resources

For anything outside the helpers, drop down to the API:

```bash
gws calendar <resource> <method> [--params '{...}'] [--json '{...}']
```

Resources: `acl`, `calendarList`, `calendars`, `channels`, `colors`, `events`, `freebusy`, `settings`. Notable `events` methods include `list`, `get`, `insert`, `update`, `patch`, `delete`, `move`, `quickAdd`, `instances`.

Discover before calling:

```bash
gws calendar --help
gws schema calendar.<resource>.<method>
```
