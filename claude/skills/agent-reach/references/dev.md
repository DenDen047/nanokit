# GitHub

`gh` is a pixi global tool and is the required way to touch github.com on this host
(see the global CLAUDE.md). Never scrape github.com with a browser fetch when `gh`
can answer.

```bash
# search
gh search repos "query" --sort stars --limit 10
gh search code "query" --language python

# repo / issues / PRs
gh repo view owner/repo
gh issue list -R owner/repo --state open
gh issue view 123 -R owner/repo
gh pr view 123 -R owner/repo
gh pr checks 123 -R owner/repo

# CI
gh run list -R owner/repo --limit 10
gh run view <run-id> -R owner/repo --log-failed

# raw API and JSON output
gh api repos/owner/repo
gh issue list -R owner/repo --json number,title --jq '.[] | "\(.number): \(.title)"'
```

Auth is already configured; if a call returns 401, report it rather than running
`gh auth login` yourself — logins are the user's step.

For "explain this repository" rather than "query this repository", the `deepwiki`
MCP answers questions about public repos without cloning.
