---
name: deepwiki
description: Use DeepWiki to build up-to-date, accurate understanding of any external tool, library, or framework before using it. Consider DeepWiki your first line of research before writing code that uses an external dependency or tool, and use it aggressively and early in the development process.
tags:
  - research
  - documentation
  - external-tools
  - cli
version: 2.2.0
---

# DeepWiki Skill

## Overview

DeepWiki (deepwiki.com) provides AI-generated wiki-style answers over public GitHub repositories. Use it before writing code against an external library, framework, tool, or API. It reflects the actual current state of the codebase — not your training data.

Use it **aggressively and early**. Do not rely on memorised knowledge for external tools; it may be stale, wrong, or version-mismatched.

The wrapper scripts in this skill are the default interface. They hide the raw JSON shape and jq extraction so agents can ask one question with one command.

---

## When to Use DeepWiki

- Understand how a library or framework works before writing code that uses it
- Verify the correct API surface, method signatures, or configuration format for a tool
- Understand architecture, data flow, or internal design of an upstream dependency
- Investigate why a particular pattern is used in a well-known codebase
- Resolve ambiguity between two approaches by checking how the authors themselves do it
- Onboard into a new technology stack quickly and accurately

**Default rule**: if you are unsure how something works in an external tool, ask DeepWiki before guessing or generating from memory.

---

## Two Access Modes

```
1. CLI (primary)  → scripts/dw-query.sh  — full capability: deep, codemap, threading
2. MCP (fallback) → mcp.deepwiki.com     — basic ask_question only, no mode selection
```

Always try the CLI first.

---

## Mode 1 — CLI (Primary)

Two scripts in `skills/deepwiki/scripts/`:

- `dw-query.sh` — ask a question; prints the answer, source files, and thread ID from one request
- `dw-status.sh` — check whether a repo is indexed; optionally warm it

### dw-query.sh

```bash
./scripts/dw-query.sh "question" owner/repo [owner/repo2 ...]
                      [--mode deep|fast|codemap] [--context "text"]
                      [--id thread-id] [--mermaid] [--sources-only] [--json]
```

One request. One response. Output:

1. **Answer prose**
2. **Sources** — file paths DeepWiki used from that same response
3. **Thread-ID** — message ID for follow-up threading with `--id`

**Always use the default mode (`deep`).** Only use `--mode fast` for quick orientation when the answer is not going into code. Use `--mode codemap` for architecture, control flow, and code trace questions.

`deep` mode can take a very long time. That is expected. Do not build short timeouts into the wrapper or assume a long wait means the query is stuck. If you intentionally want to cap waiting time for one call, wrap the script with the host `timeout` command yourself.
Otherwise, wait patiently for it to return.

#### Examples

```bash
# Standard implementation research — use this for all implementation work
./scripts/dw-query.sh "How does the plugin lifecycle work?" vitejs/vite

# If you intentionally want to cap how long you are willing to wait, do it outside the wrapper
timeout 5m ./scripts/dw-query.sh "How does the plugin lifecycle work?" vitejs/vite

# Quick orientation only
./scripts/dw-query.sh "What is this repo for?" withastro/starlight --mode fast

# Architecture and execution flow
./scripts/dw-query.sh "Show the request lifecycle" expressjs/express --mode codemap

# Mermaid diagram (codemap only) — pipe to a file to preserve the diagram
./scripts/dw-query.sh "Show how hooks execute" facebook/react --mode codemap --mermaid > diagram.mmd

# Compare multiple repos in one query
./scripts/dw-query.sh "Compare routing approaches" vitejs/vite remix-run/react-router

# Add project-specific context
./scripts/dw-query.sh "How should I structure this?" prisma/prisma \
  --context "I am using a multi-tenant SaaS with row-level security"

# Thread a follow-up using the Thread-ID from the previous response
./scripts/dw-query.sh "How does token refresh work?" supabase/supabase --id <thread-id>
```

#### Flags

| Flag | Description |
|---|---|
| `--mode deep\|fast\|codemap` | Query mode (default: `deep`) |
| `--context "text"` | Extra context injected into the query |
| `--id thread-id` | Reuse a previous Thread-ID for follow-up threading |
| `--mermaid` | Output Mermaid diagram (codemap mode only) |
| `--sources-only` | Print only source file paths, one per line |
| `--json` | Print the raw JSON response |

#### Modes

| Mode | When to use |
|---|---|
| `deep` | Default — all implementation questions; runs an agentic research loop |
| `fast` | Quick orientation only — never for implementation guidance |
| `codemap` | Architecture, data flow, execution paths — returns file-located traces |

### dw-status.sh

```bash
./scripts/dw-status.sh owner/repo [--warm]
```

Exits 0 if indexed, 1 if not. Use before querying an unfamiliar or recently created repo. Pass `--warm` to trigger indexing first (throttled to once per 10 min server-side).

```bash
./scripts/dw-status.sh vitejs/vite
./scripts/dw-status.sh withastro/starlight --warm
```

---

## Mode 2 — MCP (Fallback)

Use when the CLI scripts are unavailable (no shell access, `bunx` and `npx` not installed, or upstream API breakage).

```json
{
  "mcpServers": {
    "deepwiki": {
      "url": "https://mcp.deepwiki.com/sse"
    }
  }
}
```

Alternate endpoint if SSE fails: `https://mcp.deepwiki.com/mcp`. No API key required.

### MCP tools

#### `ask_question`

```
mcp__deepwiki__ask_question({
  repoName: "owner/repo",
  question: "How does X work?"
})
```

#### `read_wiki_structure`

Returns the table of contents. Use to survey available documentation before asking.

```
mcp__deepwiki__read_wiki_structure({ repoName: "owner/repo" })
```

#### `read_wiki_contents`

```
mcp__deepwiki__read_wiki_contents({ repoName: "owner/repo", topic: "authentication" })
```

### CLI vs MCP

| Capability | CLI | MCP |
|---|---|---|
| Deep (agentic) mode | ✅ | ❌ |
| Codemap mode | ✅ | ❌ |
| Multi-repo query | ✅ | ❌ |
| Follow-up threading | ✅ `--id` | ❌ |
| Repo index status | ✅ `dw-status.sh` | ❌ |
| Context injection | ✅ `--context` | ❌ |
| Source file listing | ✅ `--sources-only` | ❌ |

---

## Error Handling

- Repository not found: verify the `owner/repo`, check `UPSTREAM_REPOS.md`, read the upstream `README.md` on GitHub, follow README links, or do a targeted web search.
- Service unavailable: if the CLI returns upstream 502/504-style failures, retry once or twice, then fall back to `mcp__deepwiki__ask_question`, `mcp__deepwiki__read_wiki_structure`, or `mcp__deepwiki__read_wiki_contents`. If both CLI and MCP fail, use upstream docs and note the limitation.
- Long-running deep mode: expect `deep` mode to take time. Only use the host `timeout` command when you intentionally want to bound the wait for one call, for example `timeout 10m ./scripts/dw-query.sh "..." owner/repo`.
- Server-side query timeout: if DeepWiki returns a JSON error such as `{"error":"Query timed out after 240s"}`, treat it as a completed but inconclusive upstream result. Do not auto-retry the same deep query blindly; narrow the question, switch to `fast` or `codemap` if appropriate, or fall back to MCP and upstream docs.
- Courteous usage: batch related questions, reuse printed `Thread-ID` values for follow-ups, and avoid spamming warm or repeated deep queries when one threaded conversation will do.

---

## Workflow

```
1. Check UPSTREAM_REPOS.md for the canonical owner/repo.

2. If not listed:
   - Search for the canonical GitHub repo
   - Run: ./scripts/dw-status.sh owner/repo
   - If not indexed: ./scripts/dw-status.sh owner/repo --warm

3. Query (deep mode is the default):
   ./scripts/dw-query.sh "..." owner/repo

4. If the answer raises follow-up questions, thread them using the printed Thread-ID:
   ./scripts/dw-query.sh "..." owner/repo --id <thread-id>

5. Write code based on the grounded answer, not on memory.

6. Add the repo to UPSTREAM_REPOS.md if it is new to the project.
```

---

## Resolving Repo Names

Scripts require exact `owner/repo` format.

### Step 1 — Check UPSTREAM_REPOS.md first

The project maintains `./UPSTREAM_REPOS.md` mapping technologies to their canonical GitHub repo names. Always check it first.

### Step 2 — If not listed

1. Search the web for `{technology name} github`
2. Confirm the repo is official (org ownership, stars, README)
3. Run `./scripts/dw-status.sh owner/repo` to verify it is indexed

### Step 3 — Update UPSTREAM_REPOS.md

After successfully querying a new technology, **add it to UPSTREAM_REPOS.md**:

```markdown
| {display name} | {owner}/{repo} | {optional notes} |
```

---

## Query Quality

Specific, action-oriented questions produce better answers in all modes.

| Vague (avoid) | Specific (prefer) |
|---|---|
| "How does auth work?" | "What OAuth flows does this library support and how do I configure the callback URL?" |
| "Tell me about plugins" | "What is the lifecycle order of plugin hooks, and which run during build phase only?" |
| "How do I use this?" | "What is the minimal config needed to serve static files with custom cache headers?" |

Include version context when you know it. Use `--context` to add project-specific constraints when they affect the answer.

---

## Common Mistakes

| Mistake | Correct behaviour |
|---|---|
| Using MCP when the CLI works | CLI scripts are primary; MCP is the fallback |
| Using `--mode fast` for implementation work | Default to `deep`; fast is for orientation only |
| Starting a new query when a follow-up would do | Use `--id` with the Thread-ID from the previous response |
| Not checking `dw-status.sh` before querying an obscure repo | Run `dw-status.sh` first; `--warm` if not indexed |
| Guessing the repo name | Check UPSTREAM_REPOS.md, then verify with `dw-status.sh` |
| Skipping UPSTREAM_REPOS.md update | Always update it after first use of a new technology |

---

## UPSTREAM_REPOS.md Format

Maintain at the project root. Create if it does not exist.

```markdown
# Upstream Repositories

This file maps external technologies used in this project to their canonical GitHub
repository names for use with DeepWiki queries.

Update this file whenever you start using a new external tool or library.

| Technology | Upstream repo | Notes / Use for |
|---|---|---|
<!-- Add entries below -->
```

---

## Advanced Mode — Raw CLI

Use when you need streaming, custom parsing, or full JSON inspection. The wrapper scripts handle the standard case; use the raw CLI only for advanced needs or to debug a suspected API breakage.

```bash
# Stream as NDJSON
bunx @qwadratic/deepwiki-cli query "..." -r owner/repo --stream

# Save full JSON for inspection
bunx @qwadratic/deepwiki-cli query "..." -r owner/repo -m deep > /tmp/dw-raw.json

# Extract answer prose from saved JSON
jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty' /tmp/dw-raw.json

# Inspect response schema
bunx @qwadratic/deepwiki-cli query "..." -r owner/repo -m fast \
  | jq 'paths | map(tostring) | join(".")' | head -50

# Retrieve a previous query by ID
bunx @qwadratic/deepwiki-cli get <queryId>

# Search indexed repos
bunx @qwadratic/deepwiki-cli list react | jq '.indices[].repo_name'
```

Raw response schema under `.queries[0].response[]`:
- `file_contents` — `data` is `[repoName, filePath, sourceCode]`
- `chunk` / `summary_chunk` — answer prose; concatenate `.data` across all entries
- `reference` — `{ file_path, range_start, range_end }` citation
- `summary_done` / `done` — terminal markers; ignore

If the scripts stop working due to an API contract change, use the raw CLI to inspect the new schema and update the scripts accordingly.

---

## Disclaimer

This tool uses reverse-engineered, undocumented API endpoints from `api.devin.ai`. It may break at any time if Cognition changes their API. No auth is required for public repos, but rate limits may apply. If the CLI stops working, fall back to the MCP server.
