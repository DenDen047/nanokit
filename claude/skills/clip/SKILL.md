---
name: clip
description: >
  Claude Code の回答からメインコンテンツ（コード、コマンド、テキスト）を
  抽出してクリップボードにコピーする。macOS / Linux / Windows (WSL/PowerShell) 対応。
user-invocable: true
---

# Clip — クリップボードにコピー

Claude Code が生成したメインコンテンツをクリップボードにコピーし、
すぐに他のアプリに貼り付けられるようにする。

## 使い方

```
/clip              # メインコンテンツを自動検出してコピー
/clip code         # 最新のコードブロックをコピー
/clip command      # 最新のシェルコマンドをコピー
/clip <hint>       # ヒントに合致する部分をコピー
```

## 手順

1. 直近の会話から **ユーザーが貼り付けたい主要な出力** を特定する:
   - 生成されたコード（関数、クラス、設定ファイルなど）
   - シェルコマンドやワンライナー
   - テキストブロック（コミットメッセージ、PR 概要、ドキュメントなど）
   - 曖昧な場合はユーザーに確認する

2. そのコンテンツ **だけ** を抽出する:
   - 前後の説明文、マークダウンフェンス (```)、コメンタリーは除去
   - インデントとフォーマットはそのまま保持

3. 一時ファイルに書き出してからクリップボードコマンドにパイプする:
   ```bash
   # 一時ファイルに内容を書き出す
   # macOS / Linux / Windows で適切なコマンドを選択してコピー
   ```

4. コピー完了後、先頭 2 行のプレビューと合計行数を表示する。

## プラットフォーム別クリップボードコマンド

以下の優先順位で検出・使用する:

| 優先度 | 条件 | コマンド |
|--------|------|----------|
| 1 | macOS (`uname -s` = Darwin) | `pbcopy` |
| 2 | WSL (`/proc/version` に microsoft/Microsoft) | `clip.exe` または `/mnt/c/Windows/System32/clip.exe` |
| 3 | Windows (MINGW/MSYS/Cygwin) | `clip.exe` |
| 4 | Linux + Wayland (`$WAYLAND_DISPLAY` あり) | `wl-copy` |
| 5 | Linux + X11 (`$DISPLAY` あり) | `xclip -selection clipboard` |
| 6 | Linux + xsel | `xsel --clipboard --input` |
| 7 | いずれもなし | 一時ファイルのパスを表示し手動コピーを案内 |

### 検出ロジック（Bash で実装する場合）

```bash
detect_clip_cmd() {
  case "$(uname -s)" in
    Darwin)
      echo "pbcopy"
      return
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "clip.exe"
      return
      ;;
  esac
  # WSL check
  if [ -f /proc/version ] && grep -qi 'microsoft' /proc/version 2>/dev/null; then
    if command -v clip.exe >/dev/null 2>&1; then
      echo "clip.exe"
    else
      echo "/mnt/c/Windows/System32/clip.exe"
    fi
    return
  fi
  # Wayland
  if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
    echo "wl-copy"
    return
  fi
  # X11
  if [ -n "$DISPLAY" ]; then
    if command -v xclip >/dev/null 2>&1; then
      echo "xclip -selection clipboard"
      return
    elif command -v xsel >/dev/null 2>&1; then
      echo "xsel --clipboard --input"
      return
    fi
  fi
  echo ""
}
```

## ルール

- 会話全体をコピーしない。フォーカスされた貼り付け用コンテンツだけ。
- コードのインデントとフォーマットを保持する。
- 複数のコードブロックがある場合、最後の（最も関連性の高い）ものをコピーする。
  ユーザーが指定した場合はそれに従う。
- コピー対象が見つからない場合、ユーザーに何をコピーしたいか確認する。
- クリップボードコマンドが見つからない場合、一時ファイル (`/tmp/clip_output.txt`) に
  書き出してパスを案内する。
