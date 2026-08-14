# Twitter/X and Reddit

Both are read as a dedicated throwaway account, never the user's main one. Read-only,
and gently: burst traffic is what gets an account restricted.

`agent-reach doctor --json` shows whether credentials are present. It does not run a
live probe, so a populated backend means "configured", not "verified".

## Twitter/X — OpenCLI first, twitter-cli as the headless fallback

Two backends, and the choice is mechanical:

- **Chrome is running** → use `opencli`. It reads through the browser session, needs
  no cookie handling, and is the only backend whose search works.
- **Chrome is not running** → use `twitter`. Everything works except `search`.

Both read as the burner account, never the user's main one.

### OpenCLI (preferred)

```bash
opencli twitter search "query" -f yaml --limit 10
opencli twitter search "query" -f yaml --product live      # Latest tab instead of Top
opencli twitter search "query" -f yaml --from someone --exclude retweets
opencli twitter tweets USERNAME -f yaml --limit 20         # one account's recent tweets
opencli twitter profile USERNAME -f yaml                   # omit USERNAME for the logged-in account
opencli twitter timeline -f yaml --type following          # home timeline
opencli twitter article URL -f yaml
```

`search` also takes raw X operators in the query (`lang:en`, `since:YYYY-MM-DD`,
`"exact phrase"`, `OR`) and `--top-by-engagement N` to re-rank by engagement.

Check these in order when an OpenCLI call fails:

1. **Chrome must be running** with the OpenCLI extension installed and x.com logged in.
2. `opencli doctor` must report `Extension: connected`. If it says `not connected`,
   the browser side is down — report that and stop. Do not fall back to a web search
   and present the results as X data. `opencli daemon restart` clears a stale
   connection after Chrome restarts; the daemon listens on 127.0.0.1:19825.
3. Whichever X account Chrome is logged into is the one OpenCLI reads as, and it is
   meant to be the burner. `opencli twitter profile` (no argument) shows who that is.
   If it is not the burner, stop and tell the user instead of continuing.

### twitter-cli (fallback, no Chrome needed)

Cookies live in `~/.agent-reach/config.yaml`, put there by the user with
`agent-reach configure twitter-cookies`. The `twitter` wrapper on PATH
(`nanokit/tools/agent-reach/run-in-env`) passes them to the CLI as
`TWITTER_AUTH_TOKEN` / `TWITTER_CT0`, so plain `twitter ...` just works.

```bash
twitter feed -n 20                  # home timeline
twitter tweet URL_OR_ID             # one tweet with replies
twitter article URL_OR_ID
twitter user-posts @username -n 20
twitter user @username
twitter search "query"              # HTTP 404 — broken, use OpenCLI
```

`search` fails because twitter-cli builds an X transaction ID by scraping x.com's JS
and that scraper no longer matches the site (`Failed to init ClientTransaction`).
0.8.5 is the newest release on PyPI (2026-03-17), so upgrading is not a fix.

If the wrapper prints "Cookie 未設定", stop and tell the user which step is missing —
extracting cookies is their job (Cookie-Editor → Export → Header String →
`agent-reach configure twitter-cookies`). Never read cookies out of a browser
yourself, and never print the token values.

Without cookies the CLI still answers some calls through a guest token — profile
lookups and `feed` return plausible data — so **getting output back is not proof of
authentication**. The reliable tell is that wrapper message. The
`Failed to init ClientTransaction` warning is *not* a tell: it appears in every run,
authenticated or not.

## Reddit (`rdt`)

Reddit has no anonymous path: the `.json` endpoints return 403 and the official API
needs manual approval. `rdt` uses a logged-in cookie, set up once with `rdt login`.

```bash
rdt search "query" --limit 10
rdt read POST_ID                # post body + comments
rdt sub LocalLLaMA --limit 20
rdt popular --limit 10
rdt all --limit 10
```

`--yaml` gives agent-friendly output. If a call returns 403 or an empty result set,
the cookie has expired — report that and let the user re-run `rdt login`; do not try
to harvest cookies from the browser.

`rdt` also has write commands (`comment`, vote). Never call them.
