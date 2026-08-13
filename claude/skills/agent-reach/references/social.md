# Twitter/X and Reddit

Both are cookie-authenticated and both are served by a dedicated throwaway account,
not the user's main account. Read-only, and gently: burst traffic is what gets an
account restricted.

`agent-reach doctor --json` shows whether credentials are present. It does not run a
live probe, so a populated backend means "configured", not "verified".

## Twitter/X (`twitter`)

Cookies live in `~/.agent-reach/config.yaml`, put there by the user with
`agent-reach configure twitter-cookies`. The `twitter` wrapper on PATH
(`nanokit/tools/agent-reach/run-in-env`) passes them to the CLI as
`TWITTER_AUTH_TOKEN` / `TWITTER_CT0`, so plain `twitter ...` just works.

If the wrapper prints "Cookie 未設定", stop and tell the user which step is missing —
extracting cookies is their job (Cookie-Editor → Export → Header String →
`agent-reach configure twitter-cookies`). Never read cookies out of a browser
yourself, and never print the token values.

### Stable commands

```bash
twitter feed -n 20                  # home timeline — most reliable
twitter tweet URL_OR_ID             # one tweet with replies
twitter article URL_OR_ID           # X Article / long form
twitter user-posts @username -n 20
twitter user @username
```

### Checking that you are actually logged in

Without cookies the CLI still answers some calls through a guest token — profile
lookups and `feed` return plausible data — so **getting output back is not proof of
authentication**. The reliable tell is the wrapper: it prints "Cookie 未設定" on
stderr when the config holds no credentials. The
`Failed to init ClientTransaction` warning is *not* a tell — it appears in every
run, authenticated or not.

### Keyword search goes through OpenCLI, not twitter-cli

```bash
twitter search "query" -n 10        # HTTP 404 — do not use
opencli twitter search "query" -f yaml   # use this instead
```

twitter-cli builds an X transaction ID by scraping x.com's JS; that scraper is broken
against the current site (`Failed to init ClientTransaction`), which takes the search
endpoint with it. 0.8.5 is the newest release on PyPI (2026-03-17), so upgrading is
not a fix. OpenCLI drives the user's own Chrome session instead, so it is unaffected.

OpenCLI covers the rest of X too, and reads through the browser rather than raw
cookies, which is gentler on the account:

```bash
opencli twitter search "query" -f yaml
opencli twitter user-posts @account -f yaml
opencli twitter article URL -f yaml
```

Requirements, in the order to check them when something fails:

1. **Chrome must be running** with the OpenCLI extension installed and x.com logged in.
2. `opencli doctor` must show `Extension: connected`. If it says `not connected`,
   the browser side is down — report that and stop. Do not fall back to a web search
   and present the results as X data.
3. The X account Chrome is logged into is the one OpenCLI reads as. It is meant to be
   the burner. If a result looks like it came from a different account's session, stop
   and tell the user rather than continuing.

`opencli daemon` listens on 127.0.0.1:19825 and starts on demand; `opencli daemon
restart` clears a stale connection after Chrome restarts.

Use `--json` or `--yaml` for structured output. Avoid `followers` / `following`
enumeration entirely — that is the fastest way to get an account flagged.

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
