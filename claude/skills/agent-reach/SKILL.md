---
name: agent-reach
description: >
  Read and search a named internet platform: Twitter/X, Reddit, YouTube, GitHub,
  RSS feeds, or a specific web page. Use when the user names one of those platforms,
  pastes a URL from one, or asks to fetch the contents of a given page or feed —
  this skill is the single entry point for those fetches on this host, so do not
  invent an ad-hoc approach.
  NOT for open-ended research questions ("survey X", "what is the state of the art"),
  which belong to ultrasurvey / knowledge-base-query / WebSearch. NOT for writing,
  translating or analysing what was fetched. NOT for posting, commenting or liking.
allowed-tools: Bash, Read, WebFetch
---

# Agent Reach — internet fetch router

One door for "get me the contents of X" on this host. Each platform below has a chosen backend; use it instead of improvising.

Based on [Agent-Reach](https://github.com/Panniantong/Agent-Reach) 1.6.1 (rev `c70ae6d`), trimmed to the channels this host uses. Upstream 1.6 is one CLI, `agent-reach <channel> <action> [args]`, that prints one JSON object. Its other channels (XiaoHongShu, Bilibili, V2EX, Xueqiu, Xiaoyuzhou, Facebook, Instagram, LinkedIn, Boss) are not set up here: do not attempt them, and do not add them.

## Never run these

`agent-reach` comes from a pixi env at `nanokit/tools/agent-reach/`. Its wrapper `run-in-env` installs the OpenCLI version pinned in the `opencli` wrapper next to it into `.opencli/` with the env's node, and puts it first on PATH. Several `agent-reach` commands install things outside pixi or rewrite this skill:

- `agent-reach update`, `setup`, `add <channel>`, `remove`, `uninstall` — they run uv, pip or npm into `~/.agent-reach/tools/` and replace the program. Updates come from `nanokit upgrade` and a rev bump in `tools/agent-reach/pixi.toml`. If a result carries `meta.update`, ignore it. `agent-reach login twitter --import-existing` and `login reddit --import-existing` (see [references/social.md](references/social.md)) are fine, because `run-in-env` has already put the pinned OpenCLI package and the env's node on PATH and recorded the Chrome backend, so nothing gets installed.
- `agent-reach skill link|unlink` — this file in `nanokit/claude/skills/` is the single source, distributed by symlink.
- `agent-reach browser setup --retry-cloak` — it pip-installs CloakBrowser and downloads its Chromium build. The dedicated browser uses the installed Chrome on purpose (`tools/agent-reach/use-system-chrome.py`).
- `mcporter`, `pipx install`, `npm install -g` — not installed, and not to be installed.

## Routing table

Upstream's own rule is to prefer the agent's native tools for public content and use Reach for the gaps. On this host that means:

| Ask | Backend | Details |
|---|---|---|
| Web search | `exa` MCP (`web_search_exa`) | [references/search.md](references/search.md) |
| A web page / article / RSS feed | Jina Reader, scrapling MCP, feedparser | [references/web.md](references/web.md) |
| YouTube video, subtitles | `yt-dlp`, or `agent-reach youtube` | [references/video.md](references/video.md) |
| GitHub repo, code, issues, PRs | `gh` | [references/dev.md](references/dev.md) |
| Twitter/X | `agent-reach twitter` (burner login copied from the everyday Chrome) | [references/social.md](references/social.md) |
| Reddit | `agent-reach reddit --backend public-web` | [references/social.md](references/social.md) |

`agent-reach read <url>` picks the channel from a URL. `agent-reach channels` lists every action and its parameters.

## Rules

1. **Say which backend you used** — one short line, e.g. "agent-reach: Reddit via agent-reach reddit".
2. **Follow the retry chains in `references/`** on failure; do not guess at commands.
3. **Read-only.** Never post, comment, vote, like or message, even if a tool supports it.
4. **Never log in for the user** and never ask for or print passwords, cookies or other credentials. `agent-reach login <channel>` opens a window where the user logs in.
5. Snippets, page shells, comment counts and subtitle track lists are not body text, comments or subtitles; say which you have. What each platform can return at all is in [references/capabilities.md](references/capabilities.md).

## Results and errors

`ok: true` → content in `items`; each has `title / url / author / published_at / text`, upstream data in `raw`. `ok: false` → branch on `error.code` and follow `error.hint`:

| error.code | What to do |
|---|---|
| `NEED_SETUP` | Tell the user what is missing. Do not run `add` or `update` (see above) |
| `NEED_LOGIN` | Keep existing results and tell the user login is needed; they run `agent-reach login <channel>` themselves. Read [references/sessions.md](references/sessions.md) first |
| `UPSTREAM_BROKEN` | Tell the user which platform is unavailable and roughly why. Never retry in a loop |
| `TIMEOUT` | Check the failed stage with `agent-reach doctor --text`; do not retry or reopen windows in a loop |
| `RATE_LIMITED` | Reach paused the channel; the remaining wait is in `error.hint`. Wait, or use the native route from the routing table |
| `PLATFORM_BLOCKED` | The platform wants a captcha or risk check. Stop; the user resolves it on the official page |
| `BUSY` | The browser queue stayed full, or a login window is open. Retry later; do not close the window |
| `NOT_FOUND` | Content does not exist; check the link or ID |
| `BAD_INPUT` | Wrong arguments; run `agent-reach channels` |

On `PLATFORM_BLOCKED`, `RATE_LIMITED`, `NEED_LOGIN` or `BUSY`, stop this attempt; do not retry with other accounts, backends or browsers.

The `web` channel's anonymous Exa endpoint is shared and rate-limits quickly, and Reach then pauses `web` for about an hour. Reddit's public route uses the same endpoint. Prefer the native routes in the routing table for web search and page reads.

## Dedicated browser

X and Reddit run in one dedicated, headless Chrome profile under `~/.agent-reach/browser/`, separate from the user's everyday Chrome. It closes after 10 idle minutes and reopens on the next call. Login, logout and session reuse are in [references/sessions.md](references/sessions.md).

## Health check

```bash
agent-reach doctor --text          # offline status of every channel
agent-reach check <channel> --text # one live test
```

Only `github`, `youtube`, `web`, `twitter` and `reddit` matter; ignore every other row (`needs_setup` on bilibili, `unverified` on v2ex, `not_added` on the rest). `twitter` and `reddit` show `unverified` until a live check; their logins come from the everyday Chrome (see [references/social.md](references/social.md)).

If the dedicated browser reports `Port <n> belongs to an unmanaged browser`, another program holds port 9222. Do not close it; with the user's consent run `agent-reach configure browser-port <free port>`.
