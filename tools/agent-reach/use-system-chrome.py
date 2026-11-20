"""Point Agent Reach's dedicated browser at the installed Chrome instead of CloakBrowser.

Agent Reach prefers CloakBrowser, and on the first browser call it pip-installs it into ~/.agent-reach/tools/ and downloads its own Chromium build. That bypasses pixi, so run-in-env calls this once per host, before agent-reach first runs, to record the Chrome fallback that Agent Reach would otherwise choose only after the download failed. Agent Reach keeps a recorded backend and does not try CloakBrowser again unless `agent-reach browser setup --retry-cloak` is run.
"""

import sys

from agent_reach.runtime import browser

if browser._load_state().get("backend"):
    sys.exit(0)
chrome = browser._system_chrome()
if not chrome:
    # 警告だけ出して続ける。help・doctor・公開ウェブ経由の取得はブラウザ無しで動く。
    print("agent-reach: Google Chrome が見つからない。X と Reddit のサイト経由の読み取りには Chrome が要る", file=sys.stderr)
    sys.exit(0)
browser.update_state(
    backend="chrome",
    executable=chrome,
    launcher_python=None,
    fallback_reason="nanokit: pixi-only, so CloakBrowser is not installed",
)
