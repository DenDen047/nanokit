# Web search — Exa

Exa is an AI search engine, strongest on English technical content, docs and code
examples. It is registered as an HTTP MCP (`https://mcp.exa.ai/mcp`, no API key) in
both Claude Code and Codex by `nanokit agent-config-sync`.

Call the MCP tool directly:

```
web_search_exa(query: "framework API example", numResults: 5)
```

Upstream's `mcporter call exa.web_search_exa ...` is the same endpoint reached
through an npm CLI that is deliberately not installed here — use the MCP tool.

`get_code_context_exa` is deprecated upstream and not registered. For repository
contents use the GitHub search in [dev.md](dev.md), or the `deepwiki` MCP for a
question-answering view of a public repo.

## When to use what

| Need | Tool |
|---|---|
| English/technical web search, finding official docs | `exa` MCP |
| A page whose URL you already have | [web.md](web.md) |
| Code or repo metadata on GitHub | [dev.md](dev.md) |
| Broad multi-source research | not this skill — `ultrasurvey` |
