---
name: deepwiki
description: Use DeepWiki to build up-to-date, accurate understanding of any external tool, library, or framework before using it. Prefer deep AI-powered queries over surface reads. Use it as a default aid before guessing from memory.
tags:
  - research
  - documentation
  - external-tools
  - mcp
version: 1.0.0
author: Agent
---

# DeepWiki Skill

## Overview

DeepWiki (deepwiki.com) provides AI-generated wikis and semantic Q&A over any public GitHub repository. It is free, requires no authentication, and reflects the actual current state of the codebase — not your training data.

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

DeepWiki can be accessed in two ways. Use MCP when available; fall back to webfetch if MCP is not configured.

### Mode 1 — MCP (Preferred)

The official DeepWiki MCP server is available at two endpoints:

| Endpoint | Transport | Use when |
|---|---|---|
| `https://mcp.deepwiki.com/sse` | SSE (legacy) | Default; most compatible with Claude and Cursor |
| `https://mcp.deepwiki.com/mcp` | Streamable HTTP | If SSE fails or you are in an edge/Cloudflare environment |

The MCP server exposes three tools:

#### `ask_question` — Deep mode (preferred)

The most powerful tool. Submits a natural language question and returns a contextually grounded, AI-generated answer sourced from the repository's code and documentation. Internally uses DeepWiki's semantic search and the "Ask Devin" reasoning capability.

**Always prefer this tool over `read_wiki_contents` for understanding.** It reasons across the entire codebase, not just one page.

```javascript
mcp__deepwiki__ask_question({
  repoName: "owner/repo",
  question: "How does X work?"
})
```

Examples:

```javascript
mcp__deepwiki__ask_question({
  repoName: "withastro/starlight",
  question: "How do I add a custom sidebar component that persists state across pages?"
})

mcp__deepwiki__ask_question({
  repoName: "vitejs/vite",
  question: "What is the plugin execution order and how do enforce hooks work?"
})

mcp__deepwiki__ask_question({
  repoName: "prisma/prisma",
  question: "How does Prisma handle transactions and what are the isolation level guarantees?"
})
```

#### `read_wiki_structure` — Fast mode (navigation only)

Returns the table of contents for a repository's DeepWiki. Use this when you want to understand the documentation landscape before deciding what to ask, or when you need to find the name of a specific topic to fetch.

```javascript
mcp__deepwiki__read_wiki_structure({
  repoName: "owner/repo"
})
```

#### `read_wiki_contents` — Fast mode (page read)

Returns the full text of a specific wiki page. Use this for reference reading when you already know which page you want, or for retrieving a complete section to include in context.

```javascript
mcp__deepwiki__read_wiki_contents({
  repoName: "owner/repo",
  topic: "authentication"
})
```

### Mode 2 — Webfetch (Fallback)

If MCP is not available, fetch the DeepWiki page directly using your web fetch tool.

URL format:
```
https://deepwiki.com/{owner}/{repo}
https://deepwiki.com/{owner}/{repo}/{page-slug}
```

Examples:
```
https://deepwiki.com/withastro/starlight
https://deepwiki.com/vitejs/vite
https://deepwiki.com/prisma/prisma/query-engine
```

When using webfetch, fetch the main repo page first to see available sections, then fetch the specific page that is most relevant. Read the full page content, not just a summary snippet. If the page contains links to sub-pages, follow the ones that are directly relevant to your question.

---

## Error Handling

- **Repository not found**: If `mcp__deepwiki__ask_question`, `mcp__deepwiki__read_wiki_structure`, or `mcp__deepwiki__read_wiki_contents` fails because the repo name is wrong, verify the `owner/repo`, read the GitHub `README.md` directly, follow README links to docs or monorepos, and fall back to web search if the official repo is still unclear.
- **Service unavailable**: If both the MCP tools and the webfetch URL patterns (`https://deepwiki.com/{owner}/{repo}` and `https://deepwiki.com/{owner}/{repo}/{page-slug}`) fail, use the repository’s own docs, README, and linked documentation, then state briefly that DeepWiki was unavailable and what source you used instead.
- **Rate limits / courteous usage**: Batch related questions when possible, avoid repeating the same query after you already have the answer in context, and back off instead of hammering the MCP endpoints or DeepWiki pages if requests start failing intermittently.

---

## Deep vs Fast — When to Use Which

Always default to deep (`ask_question`) unless one of these conditions applies:

| Situation | Use |
|---|---|
| You have a specific question about behaviour, architecture, or usage | `ask_question` (deep) |
| You want to browse what documentation exists before asking | `read_wiki_structure` (fast) |
| You need a full reference section verbatim (e.g., a config schema) | `read_wiki_contents` (fast) |
| MCP unavailable, need to survey what pages exist | Webfetch main repo page (fast) |
| MCP unavailable, need to understand something specific | Webfetch specific sub-page (deep) |

When in doubt: use `ask_question`. It is smarter, more contextual, and more likely to give you a directly useful answer than reading a wiki page and interpreting it yourself.

---

## Resolving Repo Names

The `repoName` parameter must be the exact `owner/repo` format used on GitHub. Before calling any DeepWiki tool, confirm you have the right repo.

### Step 1 — Check UPSTREAM_REPOS.md first

The project maintains a file at `./UPSTREAM_REPOS.md` that maps technologies to their canonical GitHub repository names. **Always check this file first** when you are not fully certain of the repo name.

```markdown
<!-- Example UPSTREAM_REPOS.md -->
| Technology       | Upstream repo            | Use for                                  |
|------------------|--------------------------|------------------------------------------|
| Astro Starlight  | withastro/starlight      | Starlight docs and integration questions |
| Vite             | vitejs/vite              | Vite core behavior and plugin questions  |
| Prisma           | prisma/prisma            | Prisma schema and engine questions       |
| Fumadocs         | fuma-nama/fumadocs       | Fumadocs framework and UI questions      |
```

### Step 2 — If not in UPSTREAM_REPOS.md

If the technology is not listed, resolve the repo name by:

1. Searching the web for `{technology name} GitHub` to find the canonical repository
2. Confirming the repo exists and is the official one (check stars, org ownership, pinned README)
3. Using that name in your DeepWiki query

### Step 3 — Update UPSTREAM_REPOS.md

After successfully using DeepWiki for a new technology, **add it to UPSTREAM_REPOS.md** so future queries can skip the resolution step. Use this format:

```markdown
| Technology       | Upstream repo            | Use for                                |
|------------------|--------------------------|----------------------------------------|
| {display name}   | {owner}/{repo}           | {what this repo should answer}         |
```

Use the `Use for` column to capture contextual guidance whenever the right repo is non-obvious, multiple official repos exist, or only a specific package/subtree should be queried.

---

## Query Quality

A good `ask_question` query is specific, action-oriented, and includes relevant context. A vague question produces a vague answer.

| Vague (avoid) | Specific (prefer) |
|---|---|
| "How does auth work?" | "What OAuth flows does this library support and how do I configure the callback URL?" |
| "Tell me about plugins" | "What is the lifecycle order of plugin hooks, and which hooks run during the build phase only?" |
| "How do I use this?" | "What is the minimal configuration needed to serve static files with custom cache headers?" |
| "What are the options?" | "What configuration options affect connection pooling, and what are the recommended defaults for a high-concurrency API?" |

Include version context in your question if you know it: *"In v4, how does..."* This helps DeepWiki anchor its answer to the right codebase state.

---

## Workflow Example

When you are about to use an unfamiliar or partially familiar external tool:

```
1. Check UPSTREAM_REPOS.md for the repo name.

2. If not found:
   - Search for the canonical GitHub repo
   - Confirm it is the right one
   - Plan to update UPSTREAM_REPOS.md after use

3. Call ask_question with a targeted question about what you need to do.

4. If the answer references other concepts you do not understand,
   ask follow-up questions before writing any code.

5. Write code based on the grounded answer, not on memory.

6. Update UPSTREAM_REPOS.md with the new entry.
```

---

## Common Mistakes

| Mistake | Correct behaviour |
|---|---|
| Using `read_wiki_contents` when you have an actual question | Use `ask_question` instead |
| Guessing the repo name as `{name}/{name}` or `{name}/docs` | Check UPSTREAM_REPOS.md, then verify on GitHub |
| Asking one broad question for an entire technology | Ask one focused question per concept or task |
| Only using DeepWiki when stuck | Use DeepWiki proactively, before writing code |
| Not updating UPSTREAM_REPOS.md after a new tech is used | Always update it — the next agent (or you later) will thank you |

---

## Configuration Reference

### MCP setup (Claude Desktop / Cursor)

```json
{
  "mcpServers": {
    "deepwiki": {
      "url": "https://mcp.deepwiki.com/sse"
    }
  }
}
```

No API key, no authentication, no local installation required.

### Fallback endpoint

If `https://mcp.deepwiki.com/sse` is unreachable, switch to:
```
https://mcp.deepwiki.com/mcp
```

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

The file is append-only in normal usage. Do not remove entries. If a repo moves or is deprecated, update the `Use for` guidance to explain the new source rather than deleting the row.
