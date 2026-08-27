---
name: writing-python
description: >
  Python の実装スタイル指針。ライブラリの既定 (pixi / Ruff / Pyrefly / Polars / httpx / Typer /
  Pydantic / Plotly / Rerun / Playwright / marimo / pytest)、NumPy 形式の docstring、型ヒント、命名、クラス設計、
  `.gitignore` テンプレート。
  Python コードを書く・レビューする・リファクタするとき、Python プロジェクトを新規に作るとき、
  依存ライブラリや lint / format / 型チェック / テスト / グラフ描画のツールを選ぶときに使う。
  pixi.toml の書き方と conda-forge / PyPI の使い分けは pixi-env skill。
---

# Python 実装スタイル

対象リポジトリの既存の慣習が最優先。慣習がなければ以下を既定にする。動いているコードを新しいツールへ移すためだけの変更はしない。

## ライブラリの既定

| 用途 | 既定 | 従来のままでよい場合 |
|---|---|---|
| 環境・依存・タスク | pixi | なし (uv / Poetry / pyenv は使わない) |
| lint + format | Ruff | なし |
| 型チェック | Pyrefly | 既存が mypy。ty は 1.0 未満のうちは既定にしない (`pixi search ty`) |
| 表形式データ | Polars | pandas 前提の API と繋ぐ、既存が pandas |
| HTTP | httpx | 同期で数件叩くだけのスクリプト |
| CLI | Typer | 標準ライブラリだけで完結させたい (argparse)、細かい制御が要る (Click) |
| データ構造 | 外部から入る値は Pydantic `BaseModel`、内部だけなら dataclass | |
| 2 次元のグラフ | Plotly | 読んで終わりの静的な図は matplotlib SVG (html-report-writing skill)。読み手が値を読む・拡大する・時間を送る必要がある図は、レポート内でも Plotly |
| 3 次元データの可視化 | Rerun | |
| ブラウザ自動操作・E2E | Playwright | 既存が Selenium |
| ノートブック | marimo | チームが Jupyter を採用 |
| テスト | pytest | |

- conda-forge の Python 版 Playwright は **`playwright-python`** (`playwright` は Node 版 CLI)。ブラウザ本体は `playwright install chromium` で取得する。
- conda-forge の Rerun は **`rerun-sdk`** (import 名は `rerun`)。長時間ログを流すときはビューアに `--memory-limit` を指定する。
- marimo は依存するセルを自動で再実行するので、重い処理を再実行の対象に置かない。

## docstring

NumPy 形式。要約 1 行 + 該当する `Parameters` / `Returns` / `Raises` のみ書く。内部の短い関数は要約 1 行で足りる。本文の言語はリポジトリの既存 docstring に合わせる。規約は Ruff で固定する (下記)。

## 型と命名

- 関数・メソッドの引数には型ヒントを付ける。Pyrefly は引数の型を推論しないので、注釈が唯一の情報源になる。
- 戻り値は公開する関数・メソッドに付ける。内部の短い関数は Pyrefly の推論に任せてよい。
- `Any` で埋めない。型が決まらない場所は `object` で受けて、使う前に絞り込む。
- 外部から入る値は境界で `BaseModel` に通す。
- 型情報を名前に埋めない (`name_str` ではなく型ヒントで表す)。
- bool は真偽が読み取れる形にする (`is_student`, `has_card`, `can_login`)。
- 対になる語は正しい対義語で揃える (`start`/`stop`, `up`/`down`, `first`/`last`)。

## クラス設計

- 1 クラス 1 責務。`User` のような中心概念にアプリ中の処理を集めない。
- 基底には `ABC` + `@abstractmethod` でメソッド名と引数だけを固定し、派生ごとに違うロジックを基底に書かない。
- 一部の派生でしか使わないメソッドを基底に置かない (派生側で例外を投げて潰す形にしない)。
- 属性を特定の順で設定しないと正しく動かないメソッドを作らない。引数で受けるか、メソッドを分ける。
- 他クラスのデータの中身に依存する分岐 (`item.item_type == "food"`) は Enum にする。
- `utils` / `common` に何でも入れず、役割の分かる単位へ分ける。

リファクタリングは振る舞いを変えない範囲で、テストで前後が一致することを担保してから入れる。好みの範囲の書き換えは入れない。

## 骨格

`.gitignore` はこのスキルと同じディレクトリの `gitignore.template` をコピーして作る (Python / macOS / Windows / VS Code をまとめた gitignore.io 由来)。中身は書き換えず、プロジェクト固有の除外だけを末尾に追記する。

```bash
cp ~/.claude/skills/writing-python/gitignore.template .gitignore   # Codex は ~/.agents/skills/writing-python/
```

```toml
[tool.pixi.feature.dev.dependencies]
ruff = "*"
pyrefly = "*"
pytest = "*"

[tool.pixi.environments]
default = ["dev"]

[tool.pixi.tasks]
fmt = "ruff format ."
lint = "ruff check ."
typecheck = "pyrefly check"
test = "pytest -q"

[tool.ruff.lint]
extend-select = ["D", "ANN"]
ignore = ["ANN202"]  # 内部関数の戻り値は Pyrefly の推論に任せる

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["ANN"]

[tool.ruff.lint.pydocstyle]
convention = "numpy"
```

型チェックの設定は `pyrefly init` で作る。設定ファイルが 1 つも無いと Pyrefly は `basic` preset で動き、無注釈関数の本文を解析しない (pyrefly 1.2.0 で確認)。既存の mypy / pyright 設定があれば移行される。

出典: サプー (ライブラリ10選 / 残念なクラス設計5選 / 命名規則 / リファクタリングの基本)、各ツールの公式ドキュメント。
