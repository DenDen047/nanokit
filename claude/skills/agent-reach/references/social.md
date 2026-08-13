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

### search is unavailable (verified 2026-08-13)

```bash
twitter search "query" -n 10        # HTTP 404, even with valid cookies
```

twitter-cli builds an X transaction ID by scraping x.com's JS; that scraper is
broken against the current site (`Failed to init ClientTransaction`), which takes
the search endpoint with it. 0.8.5 is the newest release on PyPI (2026-03-17), so
upgrading is not a fix, and the upstream fallbacks (OpenCLI) are not installed here.

Work around it with the commands above: `twitter user-posts @account` for a known
source, or `twitter feed` and filter locally. If keyword search across all of X is
genuinely required, say it is unavailable rather than substituting a web search and
presenting it as X data.

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
