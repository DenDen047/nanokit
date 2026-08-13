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

One door for "get me the contents of X" on this host. Each platform below has a
chosen backend; use it instead of improvising.

Vendored from [Agent-Reach](https://github.com/Panniantong/Agent-Reach) rev
`93ae1d1`, trimmed to the channels this host actually adopted. The upstream
skill covers 15 platforms; the ones removed here (XiaoHongShu, Bilibili, V2EX,
Xueqiu, Xiaoyuzhou, Facebook, Instagram, LinkedIn) have no backend installed —
do not attempt them, and do not follow upstream instructions to install one.

## Never run these

- `agent-reach install --system` / `--channels ...` — it shells out to
  brew / apt / npm -g / pipx. This host installs shell tools only through pixi.
- `agent-reach skill --install` — it overwrites this skill directory with a copy
  and deletes the symlink that distributes it. This file in `nanokit/claude/skills/`
  is the single source.
- `mcporter`, `pipx install ...`, `npm install -g ...` — not installed, and not to be
  installed. Where upstream references say "mcporter call exa...", use the native
  `exa` MCP; where they say to npm-install OpenCLI, it is already on PATH.

`agent-reach`, `twitter`, `rdt` and `opencli` are all on PATH already — the first
three from one pixi env at `nanokit/tools/agent-reach/`, `opencli` from a
version-pinned npx wrapper in the same directory. Nothing needs installing.

## Routing table

| Ask | Backend | Details |
|---|---|---|
| Web search | `exa` MCP (`web_search_exa`) | [references/search.md](references/search.md) |
| A web page / article / RSS feed | Jina Reader, scrapling MCP, feedparser | [references/web.md](references/web.md) |
| YouTube video, subtitles, comments | `yt-dlp` | [references/video.md](references/video.md) |
| GitHub repo, code, issues, PRs | `gh` | [references/dev.md](references/dev.md) |
| Twitter/X, Reddit | `twitter` / `rdt` (cookie auth) | [references/social.md](references/social.md) |
| Keyword search across X | `opencli` (needs Chrome open) | [references/social.md](references/social.md) |

## Rules

1. **Say which backend you used** — one short line, e.g. "agent-reach: Reddit via rdt".
2. **Follow the retry chains in `references/`** on failure; do not guess at commands.
3. **Read-only.** Never post, comment, vote or like, even if the CLI supports it.
4. **Cookie-backed platforms are rate-limit sensitive.** Space Twitter/Reddit calls
   a couple of seconds apart and keep volumes modest; the accounts behind them can
   be restricted for burst traffic.
5. **Do not run `agent-reach check-update`** as a routine step. Version checks happen
   when the user asks, not after every task.

## Zero-config quick commands

```bash
# Read any web page as text
curl -s "https://r.jina.ai/URL"

# GitHub search
gh search repos "query" --sort stars --limit 10

# YouTube subtitles (~/.config/yt-dlp/config already sets --js-runtimes node)
yt-dlp --write-sub --write-auto-sub --skip-download -o "/tmp/%(id)s" "URL"
```

## Health check

```bash
agent-reach doctor          # add --json for machine-readable backends
```

`doctor` reports all 15 upstream channels, including the ones this host does not
use — a ❌ against XiaoHongShu or LinkedIn is expected and is not a problem to fix.
Only the five rows in the routing table above matter.

Two warnings are known false positives on this host; do not "fix" either:

- **YouTube "JS runtime 未設定"** — `~/.config/yt-dlp/config` does set
  `--js-runtimes node`, but it is a dotter symlink and `doctor` refuses to read
  through symlinks. Confirm with
  `yt-dlp -v --simulate "ytsearch1:test" 2>&1 | grep "User config"`.
  Writing a real file over the symlink would break the single source.
- **GitHub "未実時検証"** — `doctor` deliberately skips `gh auth status`. `gh` is
  authenticated; just use it.
- **Exa "需要 mcporter"** — Exa is registered as a native MCP instead. Ignore the
  npm install instructions.
