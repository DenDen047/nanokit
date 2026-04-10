---
name: windows-zip-extract
description: >
  Windows で作成された ZIP ファイルを macOS / Linux で展開するときの
  Deflate64 圧縮・Shift_JIS ファイル名・CP932 テキストエンコーディングの
  3 重問題を解決する。ZIP 展開で文字化けやエラーが出たときに参照する。
user-invocable: false
---

# Windows ZIP を macOS / Linux で展開する

> 実践知見: uSonar 被保険者データ展開 (2026-04) での対応をもとにまとめた。

## 問題の全体像

Windows 標準の ZIP 作成は以下の 3 つの非互換を同時に起こすことがある:

| # | 問題 | 原因 | 影響 |
|---|---|---|---|
| 1 | **展開自体が失敗** | Deflate64 (タイプ 9) 圧縮 | macOS `unzip`, Python `zipfile` が未対応 |
| 2 | **ファイル名が文字化け** | ファイル名が Shift_JIS (CP932) で記録 | UTF-8 環境でバイト列がそのまま書き出される |
| 3 | **ファイル内容が文字化け** | テキスト/CSV が Shift_JIS | `cat` / `head` で文字化け |

## 推奨手順

### Step 1: 7z で展開する

macOS `unzip` / `ditto` / Python `zipfile` は Deflate64 をサポートしない。
`p7zip` (7z コマンド) を使う。

```bash
pixi global install p7zip
7z x archive.zip -o. -aoa
```

- `-o.`: カレントディレクトリに展開
- `-aoa`: 既存ファイルを上書き

#### 圧縮タイプの確認方法

展開に失敗した場合、まず圧縮方式を確認する:

```python
import zipfile
zf = zipfile.ZipFile('archive.zip', 'r')
for info in zf.infolist():
    print(f'{info.filename}: compress_type={info.compress_type}, size={info.file_size}')
```

| タイプ | 名前 | `unzip` | Python `zipfile` | `7z` |
|---|---|---|---|---|
| 0 | Stored | OK | OK | OK |
| 8 | Deflate | OK | OK | OK |
| **9** | **Deflate64** | **NG** | **NG** | **OK** |
| 12 | BZIP2 | NG | OK | OK |
| 14 | LZMA | NG | OK | OK |

### Step 2: 文字化けファイル名をリネーム

7z は ZIP 内のファイル名バイト列をそのまま書き出す。
Shift_JIS のファイル名は `latin-1 → cp932` でデコードしてリネームする。

```python
import os

for f in os.listdir('.'):
    try:
        decoded = f.encode('latin-1').decode('cp932')
        if decoded != f:
            os.rename(f, decoded)
            print(f'Renamed: {f!r} -> {decoded}')
    except (UnicodeDecodeError, UnicodeEncodeError):
        pass  # ASCII のみのファイル名はスキップ
```

#### なぜ latin-1 → cp932 なのか

OS がファイル名を UTF-8 として解釈しようとするが、
Shift_JIS のバイト列は有効な UTF-8 ではないため、各バイトが latin-1 (ISO 8859-1)
として個別のコードポイントにマッピングされる。
`encode('latin-1')` で元のバイト列に戻し、`decode('cp932')` で正しい日本語に復元する。

### Step 3: テキストの文字コードを UTF-8 に変換

Windows 由来のテキスト/CSV ファイルは Shift_JIS (CP932) であることが多い。

```python
import pathlib

path = pathlib.Path('data.txt')
text = path.read_bytes().decode('cp932')
path.write_text(text, encoding='utf-8')
```

#### エンコーディング自動判定 (不確実な場合)

ファイルのエンコーディングが不明な場合:

```python
import chardet

with open('data.txt', 'rb') as f:
    raw = f.read(10000)  # 先頭 10KB で判定
result = chardet.detect(raw)
print(result)  # {'encoding': 'SHIFT_JIS', 'confidence': 0.99, ...}
```

`chardet` は pixi で導入: `pixi add --pypi chardet`

#### 大量ファイルの一括変換

```python
import pathlib

for p in pathlib.Path('.').glob('*.TXT'):
    try:
        text = p.read_bytes().decode('cp932')
        p.write_text(text, encoding='utf-8')
        print(f'Converted: {p}')
    except UnicodeDecodeError:
        print(f'Skipped (not CP932): {p}')
```

## 改行コードの注意

Windows テキストは改行が CRLF (`\r\n`) の場合がある。
必要に応じて LF に変換:

```python
text = text.replace('\r\n', '\n')
```

## まとめ: 3 ステップチェックリスト

1. **`7z x` で展開** — Deflate64 対応
2. **ファイル名リネーム** — `latin-1 → cp932` デコード
3. **テキスト内容を UTF-8 に変換** — `cp932 → utf-8`

すべて該当しない場合もある (例: UTF-8 で書かれた Deflate 圧縮の ZIP)。
エラーや文字化けが出た項目だけ対処すればよい。
