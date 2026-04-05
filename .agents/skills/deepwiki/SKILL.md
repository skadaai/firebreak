---
name: deepwiki
description: Use DeepWiki to build up-to-date, accurate understanding of any external tool, library, or framework before using it. Consider Deepwiki your first line of research before writing code that uses an external dependency or tool, and use it aggressively and early in the development process.
tags:
  - research
  - documentation
  - external-tools
  - cli
version: 2.0.0
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
1. CLI (primary)   → bunx @qwadratic/deepwiki-cli  — full capability: deep, codemap, threading
2. MCP (fallback)  → mcp.deepwiki.com             — basic ask_question, no mode selection
```

**Always try the CLI first.** It calls the same underlying API as Devin's DeepWiki directly, exposes all modes (deep, fast, codemap), and does not load tool descriptions into the context window on every session turn.

---

## Mode 1 — CLI (Primary)

Use via `bunx` (preferred in Nix/bun environments) or `npx`:

```bash
bunx @qwadratic/deepwiki-cli <command> [flags]
# or
npx @qwadratic/deepwiki-cli <command> [flags]
```

### Core command: `query`

```bash
bunx @qwadratic/deepwiki-cli query "<question>" -r <owner/repo> [flags]
```

**Always use `-m deep` by default.** Only downgrade to `fast` when you need a quick orientation and the answer is not going into code.

#### Deep mode (default — always use this)

```bash
bunx @qwadratic/deepwiki-cli query "How does the plugin lifecycle work?" -r vitejs/vite -m deep \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'
```

Runs an agentic research loop. Thorough, contextual, accurate. Takes longer but gives answers you can trust for implementation.

#### Fast mode (quick orientation only)

```bash
bunx @qwadratic/deepwiki-cli query "What is this repo for?" -r withastro/starlight -m fast \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'
```

Multi-hop RAG, faster but shallower. Use only for high-level orientation, not for implementation guidance.

#### Codemap mode (architecture and code flow)

```bash
bunx @qwadratic/deepwiki-cli query "Show the request lifecycle" -r expressjs/express -m codemap \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'

# With Mermaid diagram output
bunx @qwadratic/deepwiki-cli query "Show how hooks execute" -r facebook/react -m codemap --mermaid \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty' > diagram.mmd
```

Returns structured code traces with exact file locations. Use when you need to understand data flow, execution paths, or internal call chains.

#### Multi-repo query

```bash
bunx @qwadratic/deepwiki-cli query "Compare middleware approaches" -r expressjs/express -r koajs/koa -m deep \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'
```

Queries multiple repos in a single call. Use when understanding how two libraries approach the same problem.

#### Thread follow-up

```bash
# First query — note the query ID in the output JSON
bunx @qwadratic/deepwiki-cli query "How does auth work?" -r supabase/supabase -m deep \
  | tee /tmp/dw-response.json \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'

# Follow-up using the same thread
bunx @qwadratic/deepwiki-cli query "How does token refresh specifically work?" -r supabase/supabase --id <query-id-from-above> \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'
```

Reuses the research context from the previous query. Use when the first answer raises a follow-up — it is faster and more contextual than starting a new thread.

#### Additional context

```bash
bunx @qwadratic/deepwiki-cli query "How should I structure this?" -r prisma/prisma -m deep \
  -c "I am using a multi-tenant SaaS with row-level security" \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'
```

Injects extra context into the query. Use when your specific use case might affect the answer.

### Flags reference

| Flag | Description |
|---|---|
| `-r, --repo <owner/repo>` | Repo to query. Repeatable for multi-repo queries. Required. |
| `-m, --mode <mode>` | `deep` \| `fast` \| `codemap` (default: `deep`) |
| `--id <queryId>` | Thread follow-up: reuse a previous query ID |
| `-c, --context <text>` | Additional context injected into the query |
| `--mermaid` | Output Mermaid diagram (codemap mode only) |
| `-s, --stream` | Stream response chunks as NDJSON via WebSocket |
| `--no-summary` | Disable summary generation |

### Response format

The CLI outputs a **single JSON object** to stdout. The actual schema is:

```json
{
  "title": "...",
  "queries": [
    {
      "message_id": "...",
      "user_query": "...",
      "engine_id": "...",
      "repos": [{ "name": "owner/repo", "branch": "main" }],
      "response": [
        { "type": "file_contents", "data": ["vitejs/vite", "packages/vite/src/node/plugin.ts", "...source..."] },
        { "type": "chunk",         "data": "# Vite Plugin Lifecycle\n\n..." },
        { "type": "chunk",         "data": "Continuation of answer..." },
        { "type": "reference",     "data": { "file_path": "...", "range_start": 41, "range_end": 133 } },
        { "type": "summary_chunk", "data": "Summary text..." },
        { "type": "summary_done",  "data": null },
        { "type": "done",          "data": null }
      ]
    }
  ]
}
```

- `file_contents` — source files DeepWiki retrieved as context; `data` is `[repoName, filePath, sourceCode]`
- `chunk` / `summary_chunk` — the actual answer prose, split across multiple entries; concatenate to read
- `reference` — file + line range citations backing specific claims
- `summary_done` / `done` — terminal markers; ignore

### Extracting the answer

**Always pipe through jq.** The raw JSON is unreadable without it. Use the recursive descent operator `..` so the extraction is robust to any future schema changes:

```bash
# Extract and concatenate all answer prose
bunx @qwadratic/deepwiki-cli query "How does the plugin lifecycle work?" \
  -r vitejs/vite -m deep \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'

# List source files used as context
bunx @qwadratic/deepwiki-cli query "How does auth work?" -r supabase/supabase -m deep \
  | jq -r '.. | objects | select(.type? == "file_contents") | .data[1]? // empty'
```

### Management commands

Use these before querying an unfamiliar or recently updated repo:

```bash
# Check if a repo is indexed before querying it
bunx @qwadratic/deepwiki-cli status facebook/react

# Search for indexed repos matching a keyword
bunx @qwadratic/deepwiki-cli list react | jq '.indices[].repo_name'

# Pre-warm a repo's index (throttled to once per 10 min server-side)
bunx @qwadratic/deepwiki-cli warm withastro/starlight

# Retrieve a previous query result by ID
bunx @qwadratic/deepwiki-cli get <queryId>
```

### Modes at a glance

| Mode | Engine | When to use |
|---|---|---|
| `deep` | Agentic research loop | Default for all implementation questions |
| `fast` | Multi-hop RAG | Quick orientation only — never for implementation |
| `codemap` | Structured code trace | Architecture, data flow, execution paths |

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `DEEPWIKI_API_URL` | `https://api.devin.ai` | Override API base URL |

---

## Mode 2 — MCP (Fallback)

Use when the CLI is unavailable (no shell access, bunx/npx not configured, or the CLI is broken by an upstream API change).

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

Alternate endpoint if SSE fails: `https://mcp.deepwiki.com/mcp`

No API key or local installation required.

### MCP tools

#### `ask_question` — use this when falling back to MCP

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

| Capability | CLI | MCP |
|---|---|---|
| Deep (agentic) mode | ✅ `-m deep` | ❌ |
| Codemap mode | ✅ `-m codemap` | ❌ |
| Multi-repo query | ✅ multiple `-r` flags | ❌ |
| Thread follow-up | ✅ `--id` | ❌ |
| Repo index status check | ✅ `status` command | ❌ |
| Context injection | ✅ `-c` flag | ❌ |
| Structured output | ✅ JSON + jq | ❌ |

---

## Choosing a Query Mode

| Situation | Use |
|---|---|
| Implementing something using a library | CLI `-m deep` |
| Understanding architecture or call flow | CLI `-m codemap` |
| Quick orientation (what is this repo?) | CLI `-m fast` |
| Following up on a previous answer | CLI `--id <prev-id>` |
| Your use case changes the answer | CLI `-c "context here"` |
| Comparing two libraries | CLI with multiple `-r` flags |
| CLI is unavailable | MCP `ask_question` |
| Browsing docs without a specific question | MCP `read_wiki_structure` → `read_wiki_contents` |

---

## Resolving Repo Names

The `-r` flag and MCP `repoName` both require exact `owner/repo` format.

### Step 1 — Check UPSTREAM_REPOS.md first

The project maintains `./UPSTREAM_REPOS.md` mapping technologies to their canonical GitHub repo names. **Always check this file first** when you are not fully certain of the repo name.

### Step 2 — If not listed

1. Search the web for `{technology name} github`
2. Confirm the repo is official (org ownership, stars, README)
3. Run `npx @qwadratic/deepwiki-cli status {owner}/{repo}` to verify it is indexed before querying

### Step 3 — Update UPSTREAM_REPOS.md

After successfully querying a new technology, **add it to UPSTREAM_REPOS.md**:

```markdown
| {display name}   | {owner}/{repo}           | {optional notes}         |
```

Add a note when the repo name is non-obvious, when a sub-package matters more than the root, or when you had to run `warm` to trigger indexing.

---

## Query Quality

Specific, action-oriented questions produce better answers in all modes.

| Vague (avoid) | Specific (prefer) |
|---|---|
| "How does auth work?" | "What OAuth flows does this library support and how do I configure the callback URL?" |
| "Tell me about plugins" | "What is the lifecycle order of plugin hooks, and which run during build phase only?" |
| "How do I use this?" | "What is the minimal config needed to serve static files with custom cache headers?" |

Include version context when you know it: *"In v4, how does..."* Use `-c` to add project-specific context when your use case could affect the answer.

---

## Workflow

```
1. Check UPSTREAM_REPOS.md for the repo name.

2. If not found:
   - Search for the canonical GitHub repo
   - Run: npx @qwadratic/deepwiki-cli status {owner}/{repo}
   - If not indexed, run: npx @qwadratic/deepwiki-cli warm {owner}/{repo}
   - Note to update UPSTREAM_REPOS.md after use

3. Query with deep mode (default):
   npx @qwadratic/deepwiki-cli query "..." -r {owner}/{repo} -m deep

4. If the answer raises follow-up questions, thread them:
   npx @qwadratic/deepwiki-cli query "..." -r {owner}/{repo} --id <prev-id>

5. Write code based on the grounded answer, not on memory.

6. Update UPSTREAM_REPOS.md with the new entry.
```

---

## Common Mistakes

| Mistake | Correct behaviour |
|---|---|
| Using MCP when the CLI works | CLI is primary; MCP is the fallback |
| Using `-m fast` for implementation work | Default to `-m deep`; fast is for orientation only |
| Starting a new query when a follow-up would do | Use `--id` to thread on the previous result |
| Not checking `status` before querying an obscure repo | Run `status` first; `warm` if not indexed |
| Guessing the repo name | Check UPSTREAM_REPOS.md, then verify with `status` |
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
<!-- Add entries below, one per row -->
```

---

## Disclaimer

This tool uses reverse-engineered, undocumented API endpoints from `api.devin.ai`. It may break at any time if Cognition changes their API. No auth is required for public repos, but rate limits may apply. If the CLI stops working, fall back to the MCP server.
