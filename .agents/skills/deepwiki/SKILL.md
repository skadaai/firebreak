---
name: deepwiki
description: Use DeepWiki to build up-to-date, accurate understanding of any external tool, library, or framework before using it. Consider Deepwiki your first line of research before writing code that uses an external dependency or tool, and use it aggressively and early in the development process.
tags:
  - research
  - documentation
  - external-tools
  - cli
version: 2.1.0
---

# DeepWiki Skill

## Overview

DeepWiki (deepwiki.com) provides AI-generated wikis and semantic Q&A over any public GitHub repository. It is free, requires no authentication for public repos, and reflects the actual current state of the codebase — not your training data.

Use it **aggressively and early**. Whenever you are about to use an external library, framework, CLI tool, or API, consult DeepWiki first. Do not rely on memorised knowledge for external tools; it may be stale, wrong, or version-mismatched.

---

## When to Use DeepWiki

Use DeepWiki any time you need to:

- Understand how a library or framework works before writing code that uses it
- Verify the correct API surface, method signatures, or configuration format for a tool
- Understand architecture, data flow, or internal design of an upstream dependency
- Investigate why a particular pattern is used in a well-known codebase
- Resolve ambiguity between two approaches by checking how the authors themselves do it
- Onboard into a new technology stack quickly and accurately

**Default rule**: if you are unsure how something works in an external tool, ask DeepWiki before guessing or generating from memory.

---

## Two Access Modes

DeepWiki has two access modes in priority order. Use the highest available mode.

```
1. CLI (primary)   → scripts/dw-query.sh  — full capability: deep, codemap, threading
2. MCP (fallback)  → mcp.deepwiki.com    — basic ask_question, no mode selection
```

**Always try the CLI first.** It calls the same underlying API as Devin's DeepWiki directly, exposes all modes (deep, fast, codemap), and does not load tool descriptions into the context window on every session turn.

---

## Mode 1 — CLI (Primary)

Three wrapper scripts live in `skills/deepwiki/scripts/`. They each handle the `bunx` invocation and JSON extraction internally — you never need to write a raw `jq` query.

### scripts/dw-query.sh — ask a question

```
dw-query.sh "question" owner/repo [owner/repo2 ...] [--mode deep|fast|codemap]
             [--context "extra context"] [--id <prev-query-id>] [--mermaid]
```

Prints the answer to stdout.

**Always use the default mode (`deep`).** Only pass `--mode fast` when you need quick orientation and the answer is not going into code. Use `--mode codemap` for architecture, data flow, or execution path questions.

#### Examples

```bash
# Standard deep query — use this for all implementation work
./scripts/dw-query.sh "How does the plugin lifecycle work?" vitejs/vite

# Quick orientation
./scripts/dw-query.sh "What is this repo for?" withastro/starlight --mode fast

# Architecture and code flow
./scripts/dw-query.sh "Show the request lifecycle" expressjs/express --mode codemap

# With Mermaid diagram output (codemap only)
./scripts/dw-query.sh "Show how hooks execute" facebook/react --mode codemap --mermaid > diagram.mmd

# Compare two libraries
./scripts/dw-query.sh "Compare middleware approaches" expressjs/express koajs/koa

# Add project-specific context
./scripts/dw-query.sh "How should I structure this?" prisma/prisma \
  --context "I am using a multi-tenant SaaS with row-level security"

# Thread a follow-up on a previous query
./scripts/dw-query.sh "How does auth work?" supabase/supabase | tee /tmp/dw-last.txt
# (get the query ID from /tmp/dw-last.txt or the raw JSON if needed)
./scripts/dw-query.sh "How does token refresh specifically work?" supabase/supabase --id <prev-id>
```

### scripts/dw-sources.sh — list source files used as context

```
dw-sources.sh "question" owner/repo [owner/repo2 ...] [--mode MODE]
               [--context TEXT] [--id ID]
```

Prints one file path per line — the exact source files DeepWiki pulled as evidence for its answer. Useful when you want to read specific implementation files directly after getting a high-level answer.

```bash
./scripts/dw-sources.sh "How does the plugin lifecycle work?" vitejs/vite
# → packages/vite/src/node/plugin.ts
# → packages/vite/src/node/plugins/index.ts
# → packages/vite/src/node/server/pluginContainer.ts
# → ...
```

### scripts/dw-status.sh — check and warm a repo

```
dw-status.sh owner/repo [--warm]
```

Exits 0 if indexed, 1 if not. Pass `--warm` to trigger indexing first (throttled to once per 10 min server-side).

```bash
./scripts/dw-status.sh vitejs/vite
./scripts/dw-status.sh withastro/starlight --warm
```

---

## Modes at a Glance

| Mode | When to use |
|---|---|
| `deep` (default) | All implementation questions — runs an agentic research loop |
| `fast` | Quick orientation only — multi-hop RAG, never for implementation |
| `codemap` | Architecture, data flow, execution paths — returns file-located traces |

---

## Mode 2 — MCP (Fallback)

Use when the CLI scripts are unavailable (no shell access, `bunx` not configured, or upstream API breakage).

### Setup

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

#### `ask_question` — primary MCP tool

```
mcp__deepwiki__ask_question({
  repoName: "owner/repo",
  question: "How does X work?"
})
```

#### `read_wiki_structure` — navigation only

Returns the table of contents. Use to survey what documentation exists before asking.

```
mcp__deepwiki__read_wiki_structure({ repoName: "owner/repo" })
```

#### `read_wiki_contents` — page read

Returns the full text of a specific wiki page.

```
mcp__deepwiki__read_wiki_contents({ repoName: "owner/repo", topic: "authentication" })
```

### MCP limitations vs CLI

| Capability | CLI scripts | MCP |
|---|---|---|
| Deep (agentic) mode | ✅ `--mode deep` | ❌ |
| Codemap mode | ✅ `--mode codemap` | ❌ |
| Multi-repo query | ✅ multiple repos | ❌ |
| Thread follow-up | ✅ `--id` | ❌ |
| Repo index status | ✅ `dw-status.sh` | ❌ |
| Context injection | ✅ `--context` | ❌ |
| Source file listing | ✅ `dw-sources.sh` | ❌ |

---

## Choosing a Query Mode

| Situation | Use |
|---|---|
| Implementing something using a library | `dw-query.sh` (default deep mode) |
| Understanding architecture or call flow | `dw-query.sh --mode codemap` |
| Discovering which files implement a feature | `dw-sources.sh` |
| Quick orientation only | `dw-query.sh --mode fast` |
| Following up on a previous answer | `dw-query.sh --id <prev-id>` |
| Comparing two libraries | `dw-query.sh` with multiple repos |
| CLI is unavailable | MCP `ask_question` |
| Browsing docs without a specific question | MCP `read_wiki_structure` → `read_wiki_contents` |

---

## Resolving Repo Names

The scripts require exact `owner/repo` format.

### Step 1 — Check UPSTREAM_REPOS.md first

The project maintains `./UPSTREAM_REPOS.md` mapping technologies to their canonical GitHub repo names. **Always check this file first** when you are not fully certain of the repo name.

### Step 2 — If not listed

1. Search the web for `{technology name} github`
2. Confirm the repo is official (org ownership, stars, README)
3. Run `./scripts/dw-status.sh {owner}/{repo}` to verify it is indexed before querying

### Step 3 — Update UPSTREAM_REPOS.md

After successfully querying a new technology, **add it to UPSTREAM_REPOS.md**:

```markdown
| {display name}   | {owner}/{repo}           | {optional notes}         |
```

Add a note when the repo name is non-obvious, when a sub-package matters more than the root, or when you had to run `dw-status.sh --warm` to trigger indexing.

---

## Query Quality

Specific, action-oriented questions produce better answers in all modes.

| Vague (avoid) | Specific (prefer) |
|---|---|
| "How does auth work?" | "What OAuth flows does this library support and how do I configure the callback URL?" |
| "Tell me about plugins" | "What is the lifecycle order of plugin hooks, and which run during build phase only?" |
| "How do I use this?" | "What is the minimal config needed to serve static files with custom cache headers?" |

Include version context when you know it: *"In v4, how does..."* Use `--context` to add project-specific context when your use case could affect the answer.

---

## Workflow

```
1. Check UPSTREAM_REPOS.md for the repo name.

2. If not found:
   - Search for the canonical GitHub repo
   - Run: ./scripts/dw-status.sh {owner}/{repo}
   - If not indexed, run: ./scripts/dw-status.sh {owner}/{repo} --warm
   - Note to update UPSTREAM_REPOS.md after use

3. Query with deep mode (default):
   ./scripts/dw-query.sh "..." {owner}/{repo}

4. Optionally list the source files DeepWiki used:
   ./scripts/dw-sources.sh "..." {owner}/{repo}

5. If the answer raises follow-up questions, thread them:
   ./scripts/dw-query.sh "..." {owner}/{repo} --id <prev-id>

6. Write code based on the grounded answer, not on memory.

7. Update UPSTREAM_REPOS.md with the new entry.
```

---

## Common Mistakes

| Mistake | Correct behaviour |
|---|---|
| Using MCP when the CLI works | CLI scripts are primary; MCP is the fallback |
| Using `--mode fast` for implementation work | Default to `deep`; fast is for orientation only |
| Starting a new query when a follow-up would do | Use `--id` to thread on the previous result |
| Not checking `dw-status.sh` before querying an obscure repo | Run `dw-status.sh` first; `--warm` if not indexed |
| Guessing the repo name | Check UPSTREAM_REPOS.md, then verify with `dw-status.sh` |
| Skipping UPSTREAM_REPOS.md update | Always update it after a new technology is used |

---

## UPSTREAM_REPOS.md Format

Maintain this file at the project root. Create it if it does not exist.

```markdown
# Upstream Repositories

This file maps external technologies used in this project to their canonical GitHub
repository names for use with DeepWiki queries.

Update this file whenever you start using a new external tool or library.

| Technology          | Upstream repo                  | Use for                                  |
|---------------------|--------------------------------|------------------------------------------|
<!-- Add entries below, one row per technology -->
```

---

## Advanced Mode — Raw CLI

If you need to go beyond what the wrapper scripts provide (streaming, custom `jq` pipelines, saving raw JSON), call the CLI directly:

```bash
# Stream response as NDJSON
bunx @qwadratic/deepwiki-cli query "What is React?" -r facebook/react --stream

# Save full raw JSON for inspection
bunx @qwadratic/deepwiki-cli query "How does routing work?" -r vitejs/vite -m deep \
  > /tmp/dw-raw.json

# Extract answer from raw JSON
jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty' \
  /tmp/dw-raw.json

# Inspect the full response schema
bunx @qwadratic/deepwiki-cli query "..." -r vitejs/vite -m fast \
  | jq 'paths | map(tostring) | join(".")' | head -50

# Retrieve a previous query by ID
bunx @qwadratic/deepwiki-cli get <queryId>

# Search indexed repos
bunx @qwadratic/deepwiki-cli list react | jq '.indices[].repo_name'
```

The raw response schema under `.queries[0].response[]`:
- `file_contents` — `data` is `[repoName, filePath, sourceCode]`
- `chunk` / `summary_chunk` — answer prose split across entries; concatenate `.data`
- `reference` — `{ file_path, range_start, range_end }` citation
- `summary_done` / `done` — terminal markers; ignore

---

## Disclaimer

This tool uses reverse-engineered, undocumented API endpoints from `api.devin.ai`. It may break at any time if Cognition changes their API. No auth is required for public repos, but rate limits may apply. If the CLI stops working, fall back to the MCP server.
