---
name: gws-drive
description: "Google Drive: upload files and manage files, folders, and shared drives."
metadata:
  version: 0.22.5
  openclaw:
    category: "productivity"
    requires:
      bins:
        - gws
    cliHelp: "gws drive --help"
---

# drive (v3)

> **PREREQUISITE:** Read `../gws-shared/SKILL.md` for auth, global flags, and security rules.

```bash
gws drive <resource> <method> [flags]
```

Helper commands:

| Command | Purpose |
|---------|---------|
| [`+upload`](#upload) | Upload a local file with automatic metadata |

---

## +upload

> [!CAUTION]
> **Write** command — confirm with the user before executing.

```bash
gws drive +upload <file>
```

| Flag | Required | Description |
|------|----------|-------------|
| `<file>` | ✓ | Path to file to upload |
| `--parent <ID>` | — | Parent folder ID |
| `--name <NAME>` | — | Override target filename (default: source filename) |

```bash
gws drive +upload ./report.pdf
gws drive +upload ./report.pdf --parent FOLDER_ID
gws drive +upload ./data.csv --name 'Sales Data.csv'
```

MIME type is detected automatically.

---

## Raw API resources

For anything outside `+upload`, drop down to the API:

```bash
gws drive <resource> <method> [--params '{...}'] [--json '{...}']
```

Key resources:

- **`files`** — `list`, `get`, `create`, `copy`, `update`, `download`, `export`, `watch`, `listLabels`, `modifyLabels`. The workhorse.
- **`drives`** — shared drive lifecycle (`create`, `get`, `list`, `update`, `hide`, `unhide`).
- **`permissions`** — share/unshare files and drives (`create`, `update`, `delete`, `list`, `get`). ⚠️ Concurrent writes on the same file aren't supported.
- **`comments`** / **`replies`** — file comments and threaded replies.
- **`revisions`** — version history for binary files; can't delete Docs/Sheets revisions.
- `about`, `accessproposals`, `approvals`, `apps`, `changes`, `channels`, `operations` — supporting endpoints.
- `teamdrives` — deprecated, use `drives` instead.

Discover before calling:

```bash
gws drive --help
gws schema drive.<resource>.<method>
```

> **Note:** Most `files` methods require a `fields` parameter to return non-default attributes. See [Return specific fields](https://developers.google.com/workspace/drive/api/guides/fields-parameter).
