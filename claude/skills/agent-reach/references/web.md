# Web pages and RSS

## A single page (Jina Reader first)

```bash
curl -s "https://r.jina.ai/https://example.com/article"
```

Free, no key, returns Markdown-ish text. Good default for articles and docs.

### Retry chain

1. `curl -s "https://r.jina.ai/URL"` — if the body is empty, truncated, or an
   error page, continue.
2. `scrapling` MCP — `make_request` for a plain HTTP fetch, `browser_fetch_once` for
   JS-rendered or bot-protected pages (stealth Chromium, closes itself). For several
   pages on one site, `browser_open` → `browser_fetch` … → `close_session`.
3. `WebFetch` — last resort, summarises rather than returning raw text.

Stop as soon as you have the actual content; a zero exit code is not success.

## RSS / Atom

```bash
python3 -c "
import feedparser
for e in feedparser.parse('FEED_URL').entries[:5]:
    print(f'{e.title} — {e.link}')
"
```

`feedparser` ships inside the Agent Reach env, so run it through that env if the
system `python3` lacks it:

```bash
pixi run --manifest-path ~/nanokit/tools/agent-reach/pixi.toml python -c "..."
```
