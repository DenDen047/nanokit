# Twitter/X and Reddit

Both go through `agent-reach`, which drives OpenCLI inside its own dedicated, headless Chrome profile (separate from the user's everyday Chrome). Output is one JSON object; see "Results and errors" in [../SKILL.md](../SKILL.md).

## Twitter/X

X is read with the burner account only. On this host the user's everyday Chrome is logged in to X with that burner account, so the dedicated browser takes its X login from there: `agent-reach login twitter --import-existing` copies only the x.com cookies, through the OpenCLI extension in that Chrome, without opening a window. It has been done once; later calls reuse the saved session.

- If an X call returns `NEED_LOGIN`, run `agent-reach login twitter --import-existing` once and retry once. If it fails again, stop and tell the user.
- Never run `agent-reach browser use <ID>`; it switches the copy source to another browser, which may hold a different account.
- Do not use `agent-reach login twitter` (the login window) unless the user asks. X refused the burner's login from the dedicated window with "We've temporarily limited your login."
- The user's other tools on this Mac read X with the same burner account through the everyday OpenCLI. Keep volumes modest, because burst traffic from both can get the account restricted.

```bash
agent-reach twitter search "query" --limit 10
agent-reach twitter profile <username>
agent-reach twitter tweets <username> --limit 10
agent-reach twitter thread <tweet-url-or-id>     # also the way to read one post from its URL
```

`agent-reach read <x.com URL>` goes to the `web` channel, not to X, because `twitter` has no `read` action.

Upstream marks the channel experimental. A readable single post does not mean the reply stream is readable, and no action returns a complete reply tree.

## Reddit

```bash
agent-reach reddit search "query" --limit 10
agent-reach reddit read <post-url>
agent-reach reddit subreddit <name> --limit 10
agent-reach reddit search "query" --backend public-web   # anonymous public route only, no browser
```

Always pass `--backend public-web`. The Reddit login has been copied from the everyday Chrome (`agent-reach login reddit --import-existing`), but Reddit's network-security filter answers the dedicated browser's requests (`--backend opencli`, and the fall-through without a flag) with HTTP 403 and `UPSTREAM_BROKEN`; logging in again does not help. The public route uses the `web` channel's anonymous Exa endpoint, so when `web` is rate-limited, Reddit's public route is too. Then stop and tell the user; do not retry through the browser.

## Pacing

Agent Reach queues browser calls itself (at most 2 per platform, 4 in total, and 10 seconds between two searches on one platform). Still keep volumes modest: the burner account can be restricted for burst traffic.
