# JarvisLabs ツール

JarvisLabs.ai (GPU クラウド) の CLI と、案件別の費用台帳。どちらも同じ pixi env
(`./pixi.toml`) を共有し、dotter が `~/.pixi/bin/` にラッパを配って PATH に出す。

| コマンド | 実体 | 用途 |
|---|---|---|
| `jl` | `./jl` → 上流 CLI | インスタンスの作成・一時停止・破棄など |
| `jl-ledger` | `./jl-ledger` → `./ledger.py` | 案件別・月別の費用集計 |

認証はこのリポジトリの外にある。`jl setup` が書く `~/.config/jl/config.toml`、
または `JL_API_KEY` 環境変数を SDK がそのまま読む。台帳にもトークンは書かない。

## なぜ台帳が要るのか

**JarvisLabs には請求履歴 API もインスタンスのラベル/タグ機能も無い。** 費用が
読めるのは、稼働中/一時停止中のインスタンス行が持つ `cost` (そのインスタンスの
累計課金額) だけで、**破棄すると二度と取れない**。

そこで `jl-ledger snapshot` を定期的に走らせて手元に貯める。案件はインスタンス
名から割り当てる。

## 案件の帰属

インスタンス名を `<client>-<purpose>-<YYYYMMDD>` で付ける。

```
acme-sweep-20260814             → client=acme,    purpose=sweep
globex-eval-20260801            → client=globex,  purpose=eval
acme-render-20260815            → client=acme,    purpose=render
acme-multi-stage-20260901       → client=acme,    purpose=multi-stage
initech-batch-20260814-retry    → client=initech, purpose=batch
```

先頭トークンが client、**最初に現れる 8 桁の数字が日付**で、その手前までが
purpose。日付より後ろは無視する。purpose にハイフンを含めてよい。
既知クライアントとエイリアスは `~/.config/jl-ledger/clients.toml` にある
(`XDG_CONFIG_HOME` を尊重する。`JL_LEDGER_CLIENTS` でも差し替えられる)。**nanokit は
公開リポジトリなので実名はここに置かない。** 同梱の
[`clients.example.toml`](./clients.example.toml) は書式の見本で、設定が無いときの
フォールバックも兼ねる。

規約を満たすのは「2 番目以降に 8 桁の数字トークンがある」場合だけ。満たさ
ない名前や未知の client は `unattributed` に落ちるが、**集計から消えることはなく
必ず別行で出る**。理由は `list` の「帰属」列に出る (`bad_format` / `unknown_client`
/ `no_name`)。後から直せる:

```sh
jl-ledger annotate 12345 --client acme --purpose sweep
```

手で入れた帰属は以降の snapshot でも上書きされない。

上流 SDK 側の制約: **インスタンス名は 40 文字以内**で、使えるのは英数字・空白・
ハイフン・アンダースコアだけ (`jarvislabs/instances.py` の `_validate_instance_name`)。
`acme-multi-stage-20260901` で 25 文字なので通常は余裕がある。

## 使い方

```sh
jl-ledger snapshot                       # 現在のインスタンスを取り込む (唯一ネットワークを叩く)
jl-ledger report                         # 案件別 × 月別の USD 集計
jl-ledger report --month 2026-08         # 月を絞る
jl-ledger report --by purpose            # 軸を変える (client | purpose | gpu)
jl-ledger report --jpy-rate 148.5        # JPY 列を足す
jl-ledger report --json                  # 機械可読
jl-ledger list                           # 台帳の生の行 (新しい順)
```

`report` / `list` / `annotate` はオフラインで動く。

出力例:

```
JarvisLabs 費用台帳 — client 別 / 月別 (全期間, 6 インスタンス)

client        2026-07  2026-08  合計 USD
------------  -------  -------  --------
acme            11.00     2.00     13.00
globex           3.00     9.00     12.00
initech          0.00     1.00      1.00
unattributed     0.75     1.25      2.00
合計            14.75    13.25     28.00
```

JPY 換算レートは `--jpy-rate` > 環境変数 `JL_LEDGER_JPY_RATE` の順に見る。どちら
も無ければ USD だけを出す (勝手なレートは使わない)。会社の規定どおり三菱UFJ銀行の
TTS を入れる想定。**参考値なので、経理へ出す数字は税理士の側で確定させる。**

## 台帳ファイル

実体は nanokit リポジトリの外、`~/.local/state/jl-ledger/ledger.jsonl`
(`XDG_STATE_HOME` を尊重する)。1 行 1 インスタンスの JSONL で、`machine_id` が
キー。`--ledger PATH` か環境変数 `JL_LEDGER_PATH` で差し替えられる。

取り込みの規則:

- **`cost` は単調増加とみなして max を保つ。** 破棄直前に 0 や欠損が返っても、
  最後に読めた実額が残る。
- **増えた分だけをその時点の月へ積む** (`cost_by_month`)。月をまたいだ長期
  インスタンスも月別に割れる。同じ snapshot を 2 回入れると増分が 0 になるため、
  二重計上されない。**snapshot は何度実行しても安全。**
- snapshot に出てこなくなった行は `status="gone"` にして `ended_at` を入れる
  (最初の 1 回だけ)。行は消さない。
- API 呼び出しが失敗したときは何も書かない。全行が誤って `gone` になることはない。
  ただし**呼び出しが成功して 0 台だった**場合は本当に全台消えたのか区別が付かない
  ので、稼働中の行があれば警告を出したうえで `gone` にする。
- **帰属 (client / purpose) は読み出しのたびに引き直す。** クライアント表に後から
  クライアントを足せば、**既に破棄済みで二度と snapshot に出てこない行も集計に
  乗る**。`annotate` で手入力した帰属はこの引き直しでも優先される。

## 定期実行 (launchd)

15 分間隔の雛形が [`local.jl-ledger-snapshot.plist`](./local.jl-ledger-snapshot.plist)
にある。**load は自動ではしない。** 入れるときは手で:

```sh
ln -s ~/nanokit/tools/jarvislabs/local.jl-ledger-snapshot.plist \
      ~/Library/LaunchAgents/local.jl-ledger-snapshot.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.jl-ledger-snapshot.plist
launchctl kickstart -p gui/$(id -u)/local.jl-ledger-snapshot   # 動作確認
tail -f ~/.local/state/jl-ledger/snapshot.log
```

外すとき:

```sh
launchctl bootout gui/$(id -u)/local.jl-ledger-snapshot
rm ~/Library/LaunchAgents/local.jl-ledger-snapshot.plist
```

plist 側で気をつけている点:

- **中身は全部 `bash -c` の 1 行に寄せてある。** launchd は `ProgramArguments` でも
  `EnvironmentVariables` でも `StandardOutPath` でも変数を展開しないので、`$HOME` を
  bash に展開させないと雛形にユーザー名が焼き込まれる。ログの追記を
  `StandardOutPath` ではなくリダイレクトで行っているのも同じ理由。
- `bash -c` 経由という形自体は、launchd の子プロセスへ TCC の許可を継承させるため
  でもある (`~/Documents` 配下のスクリプトが EPERM で落ちる既知の問題)。
- launchd の PATH は最小限で `pixi` が見つからないため、先頭で `~/.pixi/bin` を足す。
- ログは `~/.local/state/jl-ledger/snapshot.log` に追記され、1 行 1 実行で残る。
  置き場は実行のたびに `mkdir -p` するので、事前に作らなくてよい。

**15 分間隔は取りこぼしと引き換え。** それより短命なインスタンスは台帳に載らない。
長時間の学習ジョブを想定した間隔で、詰めたいなら `StartInterval` を下げる。

## テスト

```sh
pixi run --manifest-path ~/nanokit/tools/jarvislabs/pixi.toml test
```

ネットワークにも実際の台帳ファイルにも触れない。`snapshot` が SDK を呼ぶのは
`cmd_snapshot` の中だけで、取り込みロジックは素の dict を受け取る。
