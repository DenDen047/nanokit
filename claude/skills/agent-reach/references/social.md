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

### Less stable

```bash
twitter search "query" -n 10        # X changes its GraphQL endpoints often; 404s happen
```

Retry chain for `search`: run it once more (transient failures are common), then
fall back to `twitter feed` / `twitter user-posts @someone` and filter locally.
Do not "fix" it by installing another backend.

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
