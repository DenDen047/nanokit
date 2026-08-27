#!/usr/bin/env python3
"""JarvisLabs の案件別費用台帳。

JarvisLabs には請求履歴 API もインスタンスのタグ機能も無い。費用が読めるのは
稼働中/一時停止中のインスタンス行が持つ `cost` (そのインスタンスの累計課金額)
だけで、破棄すると二度と取れない。そこで定期的に snapshot を取って手元に貯め、
インスタンス名から案件を割り当てて後から集計する。

  snapshot  現在のインスタンス一覧を台帳へ upsert する (唯一ネットワークを叩く)
  report    案件別・月別に集計する
  list      台帳の生の行を新しい順に表示する
  annotate  帰属を後から手で直す

案件は命名規約 `<client>-<purpose>-<YYYYMMDD>` から取る。規約に合わない名前や
未知の client は "unattributed" に落ちるが、集計から消すことはしない。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import tomllib
import unicodedata
from datetime import datetime
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent

# 実名のクライアント一覧は公開リポジトリの外 (config_dir) に置く。同梱するのは
# 書式の見本を兼ねたフォールバックだけ。
EXAMPLE_CLIENTS_TOML = HERE / "clients.example.toml"

UNATTRIBUTED = "unattributed"
UNKNOWN_PURPOSE = "unknown"

# 帰属できなかった理由。report / list でそのまま出して、何を直せばよいか見せる。
REASON_OK = "ok"
REASON_MANUAL = "manual"
REASON_NO_NAME = "no_name"
REASON_BAD_FORMAT = "bad_format"
REASON_UNKNOWN_CLIENT = "unknown_client"


# ── 保存先 ────────────────────────────────────────────────────────────────────


def state_dir() -> Path:
    """台帳の置き場。nanokit リポジトリの外 (XDG state) に置く。"""
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "jl-ledger"


def default_ledger_path() -> Path:
    override = os.environ.get("JL_LEDGER_PATH")
    if override:
        return Path(override).expanduser()
    return state_dir() / "ledger.jsonl"


def config_dir() -> Path:
    """クライアント表の置き場。台帳と同じくリポジトリの外 (XDG config)。"""
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(base) / "jl-ledger"


def default_clients_path() -> Path:
    override = os.environ.get("JL_LEDGER_CLIENTS")
    if override:
        return Path(override).expanduser()
    return config_dir() / "clients.toml"


def load_ledger(path: Path) -> dict[int, dict[str, Any]]:
    """台帳を machine_id → 行 の dict として読む。壊れた行は黙って捨てない。"""
    rows: dict[int, dict[str, Any]] = {}
    if not path.exists():
        return rows
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: 台帳の行を読めません: {exc}") from exc
        rows[int(row["machine_id"])] = row
    return rows


def save_ledger(path: Path, rows: dict[int, dict[str, Any]]) -> None:
    """同ディレクトリの temp へ書いて rename する。途中で落ちても台帳は壊れない。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    body = "".join(
        json.dumps(rows[mid], ensure_ascii=False, sort_keys=True) + "\n" for mid in sorted(rows)
    )
    fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(body)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


# ── 案件の帰属 ────────────────────────────────────────────────────────────────


def load_client_aliases(path: Path | None = None) -> dict[str, str]:
    """エイリアス → 正規クライアント名 の対応表を作る (小文字キー)。

    既定は `~/.config/jl-ledger/clients.toml`。無ければ同梱の
    clients.example.toml で動く。どちらも無ければ全てが unattributed に落ちる。
    """
    if path is None:
        path = default_clients_path()
        if not path.exists():
            path = EXAMPLE_CLIENTS_TOML

    table: dict[str, list[str]] = {}
    if path.exists():
        parsed = tomllib.loads(path.read_text(encoding="utf-8"))
        table = parsed.get("clients", {})

    aliases: dict[str, str] = {}
    for canonical, alias_list in table.items():
        aliases[canonical.lower()] = canonical
        for alias in alias_list or []:
            aliases[str(alias).lower()] = canonical
    return aliases


def _is_date_token(token: str) -> bool:
    return len(token) == 8 and token.isdigit()


def parse_instance_name(name: str | None, aliases: dict[str, str]) -> tuple[str, str, str]:
    """インスタンス名から (client, purpose, reason) を切り出す。

    規約は `<client>-<purpose>-<YYYYMMDD>`。先頭トークンが client、
    **最初に現れる 8 桁の数字が日付**で、その手前までが purpose。日付より後ろは
    無視する。purpose にハイフンを含められるので `acme-multi-stage-20260901`
    は purpose="multi-stage" になる。規約外でも読み取れた purpose は
    捨てずに残す (annotate で client だけ直せばよくなる)。
    """
    if not name or not name.strip():
        return UNATTRIBUTED, UNKNOWN_PURPOSE, REASON_NO_NAME

    parts = name.strip().split("-")
    date_at = next((i for i, p in enumerate(parts) if _is_date_token(p)), None)

    # 日付が 2 番目以降に無いと client と purpose を切り分けられない。
    if date_at is None or date_at < 2:
        purpose = parts[1].lower() if len(parts) >= 2 and parts[1] else UNKNOWN_PURPOSE
        return UNATTRIBUTED, purpose, REASON_BAD_FORMAT

    purpose = "-".join(parts[1:date_at]).lower() or UNKNOWN_PURPOSE

    client = aliases.get(parts[0].lower())
    if client is None:
        return UNATTRIBUTED, purpose, REASON_UNKNOWN_CLIENT

    return client, purpose, REASON_OK


# ── snapshot の取り込み ───────────────────────────────────────────────────────


def _month_of(ts: str) -> str:
    return datetime.fromisoformat(ts).strftime("%Y-%m")


def _as_number(value: Any) -> float | None:
    """数値として読めれば float、読めなければ None。runtime は文字列のこともある。"""
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def _merge_monotonic(old: Any, new: Any) -> Any:
    """単調増加とみなして大きい方を残す。数値でなければ新しい非空値を優先する。"""
    old_n, new_n = _as_number(old), _as_number(new)
    if old_n is not None and new_n is not None:
        return max(old_n, new_n)
    if new in (None, "", 0):
        return old
    return new


def _keep_latest(old: Any, new: Any) -> Any:
    """欠損しない限り新しい値で上書きする。破棄直前の欠損で情報を失わないため。"""
    return old if new is None or new == "" else new


def instance_to_view(instance: Any) -> dict[str, Any]:
    """SDK の Instance を台帳が扱う素の dict にする。SDK 依存をここだけに閉じる。"""
    d = instance.model_dump(mode="json")
    return {
        "machine_id": int(d["machine_id"]),
        "name": d.get("name"),
        "cost_usd": d.get("cost"),
        "runtime": d.get("runtime"),
        "gpu_type": d.get("gpu_type"),
        "num_gpus": d.get("num_gpus"),
        "storage_gb": d.get("storage_gb"),
        "is_spot": d.get("is_spot"),
        "template": d.get("template"),
        "fs_id": d.get("fs_id"),
        "region": d.get("region"),
        "status": d.get("status"),
    }


def merge_snapshot(
    rows: dict[int, dict[str, Any]],
    views: list[dict[str, Any]],
    now: datetime,
    aliases: dict[str, str],
) -> dict[int, dict[str, Any]]:
    """snapshot を台帳へ upsert する。同じ入力を何度入れても結果は変わらない。

    `cost` は単調増加とみなして max を保つ。増えた分だけをその時点の月へ積むので、
    月をまたいだインスタンスも月別に割れる。同じ snapshot を 2 回入れると増分が
    0 になるため、月別の値も二重計上されない。
    """
    rows = {mid: dict(row) for mid, row in rows.items()}
    stamp = now.isoformat()
    month = now.strftime("%Y-%m")
    seen: set[int] = set()

    for view in views:
        mid = int(view["machine_id"])
        seen.add(mid)
        row = rows.get(mid)

        if row is None:
            row = {
                "machine_id": mid,
                "first_seen": stamp,
                "cost_usd": 0.0,
                "cost_by_month": {},
                "manual_client": None,
                "manual_purpose": None,
                "ended_at": None,
            }

        prev_cost = float(row.get("cost_usd") or 0.0)
        new_cost = _as_number(view.get("cost_usd"))
        merged_cost = max(prev_cost, new_cost) if new_cost is not None else prev_cost
        delta = merged_cost - prev_cost
        if delta > 0:
            by_month = dict(row.get("cost_by_month") or {})
            by_month[month] = round(by_month.get(month, 0.0) + delta, 6)
            row["cost_by_month"] = by_month
        row["cost_usd"] = round(merged_cost, 6)

        row["runtime"] = _merge_monotonic(row.get("runtime"), view.get("runtime"))
        for field in ("name", "gpu_type", "num_gpus", "storage_gb", "is_spot", "template", "fs_id", "region"):
            row[field] = _keep_latest(row.get(field), view.get(field))
        row["status"] = view.get("status") or "unknown"
        # 消えた後に再び現れた行は「生きている」状態へ戻す。
        row["ended_at"] = None
        row["last_seen"] = stamp
        _apply_attribution(row, aliases)
        rows[mid] = row

    # snapshot に出てこなかった行は破棄済みとみなす。ended_at は最初の1回だけ入れる。
    for mid, row in rows.items():
        if mid in seen or row.get("status") == "gone":
            continue
        row["status"] = "gone"
        row["ended_at"] = row.get("ended_at") or stamp

    return rows


def resolve_attribution(
    rows: dict[int, dict[str, Any]], aliases: dict[str, str] | None = None
) -> dict[int, dict[str, Any]]:
    """読み出すたびに帰属を引き直す。台帳には触らない。

    クライアント表に後からクライアントを足したとき、既に破棄済みで二度と snapshot
    に出てこない行も集計に乗るようにするため。手で入れた帰属は優先されるので、
    引き直しで annotate の結果が消えることはない。
    """
    aliases = load_client_aliases() if aliases is None else aliases
    out: dict[int, dict[str, Any]] = {}
    for mid, row in rows.items():
        row = dict(row)
        _apply_attribution(row, aliases)
        out[mid] = row
    return out


def _apply_attribution(row: dict[str, Any], aliases: dict[str, str]) -> None:
    """名前から client/purpose を引き直す。手で入れた値があればそちらを優先する。"""
    client, purpose, reason = parse_instance_name(row.get("name"), aliases)
    if row.get("manual_client"):
        client, reason = row["manual_client"], REASON_MANUAL
    if row.get("manual_purpose"):
        purpose, reason = row["manual_purpose"], REASON_MANUAL
    row["client"] = client
    row["purpose"] = purpose
    row["attribution_reason"] = reason


# ── 集計 ──────────────────────────────────────────────────────────────────────


def _row_months(row: dict[str, Any]) -> dict[str, float]:
    """行の月別費用。手で書いた行など cost_by_month が無い場合は初出月へ寄せる。"""
    by_month = {k: float(v) for k, v in (row.get("cost_by_month") or {}).items()}
    if by_month:
        return by_month
    cost = float(row.get("cost_usd") or 0.0)
    if cost <= 0:
        return {}
    anchor = row.get("first_seen") or row.get("last_seen")
    return {_month_of(anchor): cost} if anchor else {}


def group_key(row: dict[str, Any], by: str) -> str:
    if by == "client":
        return row.get("client") or UNATTRIBUTED
    if by == "purpose":
        # purpose 単独だと "train" などが案件をまたいで混ざるので client と対にする。
        return f"{row.get('client') or UNATTRIBUTED}/{row.get('purpose') or UNKNOWN_PURPOSE}"
    if by == "gpu":
        gpu = row.get("gpu_type") or "unknown"
        num = row.get("num_gpus")
        return f"{gpu}x{num}" if num else gpu
    raise ValueError(f"unknown grouping: {by}")


def aggregate(
    rows: dict[int, dict[str, Any]],
    by: str = "client",
    month: str | None = None,
) -> dict[str, Any]:
    """グループ × 月 の USD 表を作る。unattributed も 1 グループとして必ず残す。"""
    groups: dict[str, dict[str, float]] = {}
    counts: dict[str, int] = {}
    months: set[str] = set()

    for row in rows.values():
        per_month = _row_months(row)
        if month is not None:
            per_month = {k: v for k, v in per_month.items() if k == month}
            if not per_month:
                continue
        key = group_key(row, by)
        counts[key] = counts.get(key, 0) + 1
        bucket = groups.setdefault(key, {})
        for m, usd in per_month.items():
            bucket[m] = round(bucket.get(m, 0.0) + usd, 6)
            months.add(m)

    ordered_months = sorted(months)
    result_rows = []
    for key in sorted(groups, key=lambda k: (k == UNATTRIBUTED or k.startswith(f"{UNATTRIBUTED}/"), k)):
        bucket = groups[key]
        result_rows.append(
            {
                "key": key,
                "instances": counts[key],
                "by_month": bucket,
                "total_usd": round(sum(bucket.values()), 6),
            }
        )

    total_by_month = {m: round(sum(g["by_month"].get(m, 0.0) for g in result_rows), 6) for m in ordered_months}
    return {
        "by": by,
        "month": month,
        "months": ordered_months,
        "rows": result_rows,
        "total": {
            "by_month": total_by_month,
            "total_usd": round(sum(total_by_month.values()), 6),
            "instances": sum(counts.values()),
        },
    }


# ── 表示 ──────────────────────────────────────────────────────────────────────


def _width(text: str) -> int:
    """全角を 2 桁として数える。日本語の見出しでも桁が揃うように。"""
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def _pad(text: str, width: int, right: bool = False) -> str:
    fill = " " * max(0, width - _width(text))
    return fill + text if right else text + fill


def render_table(headers: list[str], rows: list[list[str]], right_align: set[int] | None = None) -> str:
    right_align = right_align or set()
    widths = [max(_width(h), *(_width(r[i]) for r in rows)) if rows else _width(h) for i, h in enumerate(headers)]
    lines = ["  ".join(_pad(h, widths[i], i in right_align) for i, h in enumerate(headers))]
    lines.append("  ".join("-" * w for w in widths))
    for row in rows:
        lines.append("  ".join(_pad(c, widths[i], i in right_align) for i, c in enumerate(row)))
    return "\n".join(line.rstrip() for line in lines)


def _usd(value: float) -> str:
    return f"{value:,.2f}"


def _jpy(value_usd: float, rate: float) -> int:
    """USD を円に丸める。Python 既定の銀行家丸めではなく四捨五入にする。"""
    return int(value_usd * rate + 0.5)


def resolve_jpy_rate(explicit: float | None) -> float | None:
    if explicit is not None:
        return explicit
    env = os.environ.get("JL_LEDGER_JPY_RATE")
    if not env:
        return None
    try:
        return float(env)
    except ValueError:
        print(f"警告: JL_LEDGER_JPY_RATE を数値として読めません: {env!r}", file=sys.stderr)
        return None


# ── サブコマンド ──────────────────────────────────────────────────────────────


def cmd_snapshot(args: argparse.Namespace) -> int:
    from jarvislabs import Client  # ネットワークを使うのはここだけ。他はオフラインで動く。

    with Client() as client:
        instances = client.instances.list()

    views = [instance_to_view(inst) for inst in instances]
    path = args.ledger
    before = load_ledger(path)

    # 空の応答は「全部消した」と「API が一時的に空を返した」の区別が付かない。
    # 前者なら正しい動作なのでそのまま進めるが、後者だと全行が gone に落ちるので
    # 黙って通さない。次の snapshot で復帰はするが、気づけないのが困る。
    live_before = [mid for mid, row in before.items() if row.get("status") != "gone"]
    if not views and live_before:
        print(
            f"警告: 応答が 0 台でしたが、台帳には稼働中の行が {len(live_before)} 件あります。"
            f"全て gone として記録します (machine_id: {sorted(live_before)})。",
            file=sys.stderr,
        )

    now = datetime.now().astimezone()
    after = merge_snapshot(before, views, now, load_client_aliases())
    save_ledger(path, after)

    new_ids = set(after) - set(before)
    gone_now = [
        mid for mid, row in after.items() if row.get("status") == "gone" and before.get(mid, {}).get("status") != "gone"
    ]
    total = sum(float(r.get("cost_usd") or 0.0) for r in after.values())
    print(
        f"[{now.isoformat(timespec='seconds')}] snapshot: 稼働 {len(views)} 台 "
        f"(新規 {len(new_ids)} / 消失 {len(gone_now)}) 台帳 {len(after)} 行 "
        f"累計 ${_usd(total)} → {path}"
    )
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    rows = resolve_attribution(load_ledger(args.ledger))
    result = aggregate(rows, by=args.by, month=args.month)
    rate = resolve_jpy_rate(args.jpy_rate)

    if args.json:
        payload = dict(result)
        payload["jpy_rate"] = rate
        if rate is not None:
            for row in payload["rows"]:
                row["total_jpy"] = _jpy(row["total_usd"], rate)
            # 合計は行の円額の和。USD 合計から別に丸めると列が合わなくなる。
            payload["total"]["total_jpy"] = sum(row["total_jpy"] for row in payload["rows"])
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    if not rows:
        print(f"台帳が空です ({args.ledger})。まず `jl-ledger snapshot` を実行してください。")
        return 0
    if not result["rows"]:
        print(f"該当する行がありません (month={args.month})。")
        return 0

    months = result["months"]
    headers = [args.by] + months + ["合計 USD"]
    right = {i for i in range(1, len(headers))}
    if rate is not None:
        headers.append("合計 JPY")
        right.add(len(headers) - 1)

    table_rows = []
    jpy_total = 0
    for row in result["rows"]:
        cells = [row["key"]] + [_usd(row["by_month"].get(m, 0.0)) for m in months] + [_usd(row["total_usd"])]
        if rate is not None:
            jpy = _jpy(row["total_usd"], rate)
            jpy_total += jpy
            cells.append(f"{jpy:,}")
        table_rows.append(cells)

    total = result["total"]
    total_cells = ["合計"] + [_usd(total["by_month"].get(m, 0.0)) for m in months] + [_usd(total["total_usd"])]
    if rate is not None:
        # 各行を丸めてから足す。USD 合計を別に丸めると列が 1 円合わなくなる。
        total_cells.append(f"{jpy_total:,}")
    table_rows.append(total_cells)

    scope = f"{args.month} のみ" if args.month else "全期間"
    print(f"JarvisLabs 費用台帳 — {args.by} 別 / 月別 ({scope}, {total['instances']} インスタンス)\n")
    print(render_table(headers, table_rows, right_align=right))

    unattributed = sum(
        r["total_usd"] for r in result["rows"] if r["key"] == UNATTRIBUTED or r["key"].startswith(f"{UNATTRIBUTED}/")
    )
    if unattributed > 0:
        print(
            f"\n注意: 帰属不明が ${_usd(unattributed)} あります。"
            "\n      `jl-ledger list` で該当行を確認し、`jl-ledger annotate <machine_id> --client X --purpose Y` で直せます。"
        )
    if rate is not None:
        print(f"\nJPY 換算レート: 1 USD = {rate} JPY (参考値)")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    rows = resolve_attribution(load_ledger(args.ledger))
    ordered = sorted(rows.values(), key=lambda r: (r.get("last_seen") or "", r["machine_id"]), reverse=True)
    if args.limit:
        ordered = ordered[: args.limit]

    if args.json:
        print(json.dumps(ordered, ensure_ascii=False, indent=2))
        return 0

    if not ordered:
        print(f"台帳が空です ({args.ledger})。まず `jl-ledger snapshot` を実行してください。")
        return 0

    headers = ["machine_id", "name", "client", "purpose", "gpu", "status", "USD", "first_seen", "last_seen", "帰属"]
    table_rows = [
        [
            str(r["machine_id"]),
            str(r.get("name") or "-"),
            str(r.get("client") or "-"),
            str(r.get("purpose") or "-"),
            group_key(r, "gpu"),
            str(r.get("status") or "-"),
            _usd(float(r.get("cost_usd") or 0.0)),
            (r.get("first_seen") or "-")[:16],
            (r.get("last_seen") or "-")[:16],
            str(r.get("attribution_reason") or "-"),
        ]
        for r in ordered
    ]
    print(render_table(headers, table_rows, right_align={0, 6}))
    return 0


def cmd_annotate(args: argparse.Namespace) -> int:
    if args.client is None and args.purpose is None:
        print("--client か --purpose のどちらかは必要です。", file=sys.stderr)
        return 2

    path = args.ledger
    rows = load_ledger(path)
    row = rows.get(args.machine_id)
    if row is None:
        print(f"machine_id {args.machine_id} は台帳にありません。`jl-ledger list` で確認してください。", file=sys.stderr)
        return 1

    aliases = load_client_aliases()
    if args.client is not None:
        if args.client.lower() not in aliases and args.client != UNATTRIBUTED:
            print(
                f"警告: '{args.client}' は {default_clients_path()} に無いクライアントです。"
                "そのまま記録します。",
                file=sys.stderr,
            )
        row["manual_client"] = aliases.get(args.client.lower(), args.client)
    if args.purpose is not None:
        row["manual_purpose"] = args.purpose

    _apply_attribution(row, aliases)
    rows[args.machine_id] = row
    save_ledger(path, rows)
    print(f"{args.machine_id}: client={row['client']} purpose={row['purpose']} (手動)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--ledger",
        type=lambda p: Path(p).expanduser(),
        default=default_ledger_path(),
        help="台帳ファイルのパス (既定: $XDG_STATE_HOME/jl-ledger/ledger.jsonl)",
    )

    parser = argparse.ArgumentParser(prog="jl-ledger", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p_snap = sub.add_parser("snapshot", parents=[common], help="現在のインスタンス一覧を台帳へ取り込む")
    p_snap.set_defaults(func=cmd_snapshot)

    p_report = sub.add_parser("report", parents=[common], help="案件別・月別に集計する")
    p_report.add_argument("--month", help="対象月 (YYYY-MM)")
    p_report.add_argument("--by", choices=["client", "purpose", "gpu"], default="client", help="集計の軸")
    p_report.add_argument("--jpy-rate", type=float, help="JPY 換算レート (既定: 環境変数 JL_LEDGER_JPY_RATE)")
    p_report.add_argument("--json", action="store_true", help="JSON で出力する")
    p_report.set_defaults(func=cmd_report)

    p_list = sub.add_parser("list", parents=[common], help="台帳の生の行を新しい順に表示する")
    p_list.add_argument("--limit", type=int, help="表示する行数の上限")
    p_list.add_argument("--json", action="store_true", help="JSON で出力する")
    p_list.set_defaults(func=cmd_list)

    p_ann = sub.add_parser("annotate", parents=[common], help="帰属を手で直す")
    p_ann.add_argument("machine_id", type=int)
    p_ann.add_argument("--client")
    p_ann.add_argument("--purpose")
    p_ann.set_defaults(func=cmd_annotate)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
