# Twitter/X and Reddit

Both go through `agent-reach`, which drives OpenCLI inside its own dedicated, headless Chrome profile (separate from the user's everyday Chrome). Output is one JSON object; see "Results and errors" in [../SKILL.md](../SKILL.md).

## Twitter/X

X is read with the burner account only. The user logs it in once with `agent-reach login twitter`, which adds the channel, opens the dedicated window and records the login as manual. Until that has happened, any browser-backed `twitter` call copies the X login from the user's everyday Chrome (if it is connected to the OpenCLI extension) and reads X as the main account. So:

- If `agent-reach doctor --text` shows `twitter` as `not_added`, do not call `agent-reach twitter`. Ask the user to run `agent-reach login twitter` and log in with the burner account.
- Never run `agent-reach login twitter --import-existing` or `agent-reach browser use <ID>`; both copy a login from another browser.

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

Until the user has run `agent-reach login reddit`, always pass `--backend public-web`. Without it, a failed public attempt falls through to the dedicated browser, which copies the Reddit login from the user's everyday Chrome if one exists. The same fall-through applies to `twitter`, which is why X is not called before its login. After `login reddit`, search and read go to the dedicated browser first, as that account; `--backend public-web` still forces an anonymous lookup. The public route shares the `web` channel's anonymous Exa endpoint, so when `web` is rate-limited, Reddit's public route is too.

## Pacing

Agent Reach queues browser calls itself (at most 2 per platform, 4 in total, and 10 seconds between two searches on one platform). Still keep volumes modest: the burner account can be restricted for burst traffic.
