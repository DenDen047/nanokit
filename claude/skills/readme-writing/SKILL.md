---
name: readme-writing
description: Use this skill when creating or updating a README file. Covers the funnel structure (What → Why → Install → How), keeping it concise, and separating concerns into dedicated files (CONTRIBUTING.md, CHANGELOG.md).
user-invocable: true
---

# README Writing: 読まれるREADMEの構造

> 出典: [MIT Missing Semester 2026 - Beyond the Code](https://missing.csail.mit.edu/2026/beyond-code/)
> 参考: [fantoccini](https://github.com/jonhoo/fantoccini), [HdrHistogram_rust](https://github.com/HdrHistogram/HdrHistogram_rust), [loguru](https://github.com/Delgan/loguru)

## 基本原則

**READMEはファネル（漏斗）構造で書く。** 上から順に読んで、必要な段階で離脱できるようにする。
読者の時間を尊重し、最小限の情報で判断できるようにする。

## 推奨構造

```
# プロジェクト名          ← 1行キャッチフレーズ（What）
[バッジ行]               ← CI / version / license / coverage（任意）
[ビジュアルデモ]          ← スクリーンショット / GIF / 端末出力（任意）

## Installation           ← すぐ試せるように短く
## Usage / Quick Start    ← コード例主体、段階的に複雑化
## Features（任意）       ← 量が多いプロジェクト向け
## Contributing（短く）   ← 詳細は CONTRIBUTING.md へ
## License               ← 1行 + LICENSE ファイルへのリンク
```

### Why セクションについて

独立した「Why」セクションは不要な場合が多い。冒頭の1行説明やイントロ段落に
「何を解決するか」を自然に織り込む方が、実際のOSSプロジェクトでは一般的。

## 各セクションの書き方

### 1. What — プロジェクト名 + 1行説明

H1タイトルの直後に、1〜2文で「これは何か」を示す。

冒頭の記載例:

```markdown
# fantoccini

A high-level API for programmatically interacting with web pages
through WebDriver.
```

```markdown
# loguru

Python logging made (stupidly) simple.
```

プロジェクト名だけで伝わらない場合は、対象ユーザーや解決する課題を含める。
可能ならビジュアルデモ（スクリーンショット、GIF、端末出力）を添える。

### 2. バッジ（任意）

バッジは冒頭またはタイトル直下にまとめる。よく使われるもの:

```markdown
[![Crates.io](https://img.shields.io/crates/v/fantoccini.svg)](https://crates.io/crates/fantoccini)
[![Documentation](https://docs.rs/fantoccini/badge.svg)](https://docs.rs/fantoccini/)
[![codecov](https://codecov.io/gh/jonhoo/fantoccini/graph/badge.svg)](https://codecov.io/gh/jonhoo/fantoccini)
```

バッジは3〜5個程度に抑える。多すぎると視認性が落ちる。

### 3. Installation

短く。コピー&ペーストで完了する形にする。

```markdown
## Installation

```bash
pip install loguru
```
```

前提条件がある場合は箇条書きで添える:

```markdown
Requirements: git, curl
```

### 4. Usage / Quick Start

**コード例を主体にする。** 説明文で語るより、動くコードを見せる。

段階的に複雑化させる（loguru方式）:

```markdown
## Usage

基本的な使い方:

```python
from loguru import logger
logger.debug("That's it, beautiful and simple logging!")
```

ファイル出力:

```python
logger.add("file_{time}.log")
```

ローテーション:

```python
logger.add("file.log", rotation="500 MB")
logger.add("file.log", rotation="12:00")
```
```

複数の例を出す場合は、シンプルなものから始めて徐々に高度にする。
各コード例には1〜2行の説明を付けると理解しやすい。

### 5. Features（任意）

機能が多いプロジェクトでは、各機能を独立したサブセクションにし、
それぞれにコード例を付ける（loguru方式が好例）。

機能が少ないプロジェクトでは Usage に統合してよい。

### 6. 設計判断・制限事項（任意）

「なぜこうしたか」を明示すると、ユーザーがプロジェクトの適合性を判断しやすい。

```markdown
## Design decisions

- Uses quantiles `[0,1]` instead of percentiles `[0,100]`
  to minimize floating-point precision loss
- Safe functions return `Result`; operator overloads panic on error
```

未実装機能や既知の制限も正直に書く（HdrHistogram_rust方式）。

### 7. Contributing

README内では短く。詳細は `CONTRIBUTING.md` に分離する。

```markdown
## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
```

テストの実行方法だけREADMEに書くパターンも有効:

```markdown
## Contributing

```bash
chromedriver &
geckodriver &
cargo test
```
```

### 8. License

1行 + ファイルリンク。デュアルライセンスの場合も簡潔に。

```markdown
## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE)
or [MIT license](LICENSE-MIT) at your option.
```

## README以外に分離するもの

| 内容 | ファイル | 理由 |
|---|---|---|
| 貢献ガイド | `CONTRIBUTING.md` | 対象読者が限定的 |
| 変更履歴 | `CHANGELOG.md` | 量が増え続ける |
| アーキテクチャ | `docs/` | 開発者向け詳細情報 |
| API仕様 | `docs/` または自動生成 | READMEに書くと古くなる |
| FAQ | `FAQ.md` または `docs/` | 量が多ければ分離 |

## アンチパターン

- **全部入りREADME**: アーキテクチャ、API仕様、デプロイ手順を全て1ファイルに詰め込む
- **インストール先頭型**: What の説明より前にインストール手順を置く
- **説明過多**: コード例で示せることを長文で説明する
- **コード例なし**: 使い方が文章だけで、コピペして試せない
- **更新されないREADME**: コードは変わったがREADMEは初版のまま
