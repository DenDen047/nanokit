"""ledger.py の単体テスト。ネットワークにも実際の台帳ファイルにも触れない。

snapshot が SDK を呼ぶのは cmd_snapshot の中だけで、取り込みロジック
(merge_snapshot) は素の dict を受け取るため、SDK 無しで全て検証できる。
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

import ledger

JST = timezone(timedelta(hours=9))
T0 = datetime(2026, 7, 20, 10, 0, tzinfo=JST)
T1 = datetime(2026, 7, 20, 12, 0, tzinfo=JST)
T2 = datetime(2026, 8, 1, 9, 0, tzinfo=JST)

ALIASES = ledger.load_client_aliases(ledger.EXAMPLE_CLIENTS_TOML)


def view(machine_id: int, name: str | None, cost: float, **overrides) -> dict:
    """snapshot 1 台分。SDK の Instance を instance_to_view で潰した後の形。"""
    base = {
        "machine_id": machine_id,
        "name": name,
        "cost_usd": cost,
        "runtime": 3600,
        "gpu_type": "A100",
        "num_gpus": 1,
        "storage_gb": 100,
        "is_spot": False,
        "template": "pytorch",
        "fs_id": None,
        "region": "IN1",
        "status": "Running",
    }
    base.update(overrides)
    return base


# ── 名前のパース ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "name,expected",
    [
        ("acme-sweep-20260814", ("acme", "sweep", ledger.REASON_OK)),
        ("globex-eval-20260801", ("globex", "eval", ledger.REASON_OK)),
        # 日付より後ろは無視する。
        ("initech-batch-20260814-retry", ("initech", "batch", ledger.REASON_OK)),
        # 大小文字は無視して正規名へ寄せる。
        ("ACME-Sweep-20260814", ("acme", "sweep", ledger.REASON_OK)),
        # purpose にハイフンを含めてよい。
        ("acme-multi-stage-20260901", ("acme", "multi-stage", ledger.REASON_OK)),
        ("acme-render-20260815", ("acme", "render", ledger.REASON_OK)),
        # 日付より後ろに数字らしきものが続いても、最初の日付で切る。
        ("globex-infer-20260801-20260802", ("globex", "infer", ledger.REASON_OK)),
    ],
)
def test_parse_conforming_names(name, expected):
    assert ledger.parse_instance_name(name, ALIASES) == expected


@pytest.mark.parametrize(
    "alias,canonical",
    [("acmecorp", "acme"), ("ac", "acme"), ("initechlabs", "initech"), ("gbx", "globex")],
)
def test_parse_alias_maps_to_canonical_client(alias, canonical):
    client, purpose, reason = ledger.parse_instance_name(f"{alias}-train-20260814", ALIASES)
    assert (client, purpose, reason) == (canonical, "train", ledger.REASON_OK)


@pytest.mark.parametrize(
    "name,reason",
    [
        ("scratch", ledger.REASON_BAD_FORMAT),  # ハイフンなし
        ("acme-sweep", ledger.REASON_BAD_FORMAT),  # 日付が無い
        ("acme-sweep-notadate", ledger.REASON_BAD_FORMAT),  # 日付トークンが無い
        ("acme-sweep-2026081", ledger.REASON_BAD_FORMAT),  # 7 桁
        ("20260814-acme-sweep", ledger.REASON_BAD_FORMAT),  # 日付が先頭。client を切り出せない
        ("acme-20260814", ledger.REASON_BAD_FORMAT),  # purpose が無い
        ("nosuchclient-train-20260814", ledger.REASON_UNKNOWN_CLIENT),  # 未知のクライアント
    ],
)
def test_parse_non_conforming_names_fall_back_to_unattributed(name, reason):
    client, _purpose, got_reason = ledger.parse_instance_name(name, ALIASES)
    assert client == ledger.UNATTRIBUTED
    assert got_reason == reason


def test_parse_keeps_purpose_even_when_unattributed():
    """client が引けなくても purpose は捨てない。annotate で client だけ直せる。"""
    client, purpose, _ = ledger.parse_instance_name("nosuchclient-train-20260814", ALIASES)
    assert (client, purpose) == (ledger.UNATTRIBUTED, "train")


@pytest.mark.parametrize("name", [None, "", "   "])
def test_parse_missing_name(name):
    assert ledger.parse_instance_name(name, ALIASES) == (
        ledger.UNATTRIBUTED,
        ledger.UNKNOWN_PURPOSE,
        ledger.REASON_NO_NAME,
    )


# ── upsert の冪等性 ───────────────────────────────────────────────────────────


def test_snapshot_upsert_is_idempotent():
    views = [view(1, "acme-sweep-20260814", 1.50)]
    once = ledger.merge_snapshot({}, views, T0, ALIASES)
    twice = ledger.merge_snapshot(once, views, T0, ALIASES)

    assert len(twice) == 1
    assert twice[1]["cost_usd"] == 1.50
    # 同じ snapshot を 2 回入れても月別が二重計上されない。
    assert twice[1]["cost_by_month"] == {"2026-07": 1.50}
    assert twice[1]["first_seen"] == T0.isoformat()


def test_repeated_snapshots_keep_first_seen_and_advance_last_seen():
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 1.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [view(1, "acme-a-20260720", 2.0)], T1, ALIASES)

    assert rows[1]["first_seen"] == T0.isoformat()
    assert rows[1]["last_seen"] == T1.isoformat()
    assert rows[1]["cost_usd"] == 2.0


def test_cost_is_kept_as_max_when_a_lower_value_arrives():
    """破棄直前などに cost が 0 や小さい値で返ってきても、最後の実額を失わない。"""
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 5.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [view(1, "acme-a-20260720", 0.0)], T1, ALIASES)

    assert rows[1]["cost_usd"] == 5.0
    assert rows[1]["cost_by_month"] == {"2026-07": 5.0}


def test_runtime_is_kept_as_max():
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 1.0, runtime=7200)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [view(1, "acme-a-20260720", 1.0, runtime=60)], T1, ALIASES)

    assert rows[1]["runtime"] == 7200


def test_runtime_falls_back_to_latest_when_not_numeric():
    """API は runtime に "hour" のような文字列を返すことがある (duration の別名)。"""
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 1.0, runtime="hour")], T0, ALIASES)
    assert rows[1]["runtime"] == "hour"


# ── 消失の記録 ────────────────────────────────────────────────────────────────


def test_missing_instance_is_marked_gone():
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 3.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [], T1, ALIASES)

    assert rows[1]["status"] == "gone"
    assert rows[1]["ended_at"] == T1.isoformat()
    # 破棄後も最後に読めた実額が残る。
    assert rows[1]["cost_usd"] == 3.0


def test_ended_at_is_not_overwritten_by_later_snapshots():
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 3.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [], T1, ALIASES)
    rows = ledger.merge_snapshot(rows, [], T2, ALIASES)

    assert rows[1]["ended_at"] == T1.isoformat()


def test_other_rows_survive_a_snapshot_that_lists_only_one_instance():
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 1.0), view(2, "globex-b-20260720", 2.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [view(1, "acme-a-20260720", 1.5)], T1, ALIASES)

    assert rows[2]["status"] == "gone"
    assert rows[2]["cost_usd"] == 2.0
    assert rows[1]["status"] == "Running"


# ── 月別の割り付け ────────────────────────────────────────────────────────────


def test_cost_increment_is_attributed_to_the_month_it_accrued_in():
    """月をまたいだインスタンスは、増えた分だけがその月に積まれる。"""
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 10.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [view(1, "acme-a-20260720", 25.0)], T2, ALIASES)

    assert rows[1]["cost_by_month"] == {"2026-07": 10.0, "2026-08": 15.0}
    assert rows[1]["cost_usd"] == 25.0


def test_aggregate_by_client_and_month():
    rows = ledger.merge_snapshot(
        {},
        [
            view(1, "acme-sweep-20260720", 10.0),
            view(2, "acme-train-20260720", 5.0),
            view(3, "globex-infer-20260720", 2.0),
        ],
        T0,
        ALIASES,
    )
    rows = ledger.merge_snapshot(
        rows,
        [view(1, "acme-sweep-20260720", 12.0), view(3, "globex-infer-20260720", 4.5)],
        T2,
        ALIASES,
    )

    result = ledger.aggregate(rows, by="client")
    got = {r["key"]: r for r in result["rows"]}

    assert result["months"] == ["2026-07", "2026-08"]
    assert got["acme"]["by_month"] == {"2026-07": 15.0, "2026-08": 2.0}
    assert got["acme"]["total_usd"] == 17.0
    assert got["globex"]["by_month"] == {"2026-07": 2.0, "2026-08": 2.5}
    assert result["total"]["total_usd"] == 21.5


def test_aggregate_filtered_to_one_month():
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 10.0)], T0, ALIASES)
    rows = ledger.merge_snapshot(rows, [view(1, "acme-a-20260720", 25.0)], T2, ALIASES)

    august = ledger.aggregate(rows, by="client", month="2026-08")
    assert august["rows"] == [{"key": "acme", "instances": 1, "by_month": {"2026-08": 15.0}, "total_usd": 15.0}]
    assert august["total"]["total_usd"] == 15.0


def test_aggregate_by_purpose_keeps_clients_apart():
    """purpose 単独だと "train" が案件をまたいで混ざるので client と対で数える。"""
    rows = ledger.merge_snapshot(
        {},
        [view(1, "acme-train-20260720", 3.0), view(2, "globex-train-20260720", 4.0)],
        T0,
        ALIASES,
    )
    keys = {r["key"]: r["total_usd"] for r in ledger.aggregate(rows, by="purpose")["rows"]}
    assert keys == {"acme/train": 3.0, "globex/train": 4.0}


def test_aggregate_by_gpu():
    rows = ledger.merge_snapshot(
        {},
        [
            view(1, "acme-a-20260720", 3.0, gpu_type="A100", num_gpus=1),
            view(2, "globex-b-20260720", 4.0, gpu_type="L4", num_gpus=1),
            view(3, "initech-c-20260720", 1.0, gpu_type="L4", num_gpus=1),
        ],
        T0,
        ALIASES,
    )
    keys = {r["key"]: r["total_usd"] for r in ledger.aggregate(rows, by="gpu")["rows"]}
    assert keys == {"A100x1": 3.0, "L4x1": 5.0}


def test_unattributed_stays_in_the_report():
    rows = ledger.merge_snapshot(
        {},
        [view(1, "acme-a-20260720", 3.0), view(2, "scratch", 7.0), view(3, "nosuchclient-train-20260720", 1.0)],
        T0,
        ALIASES,
    )
    result = ledger.aggregate(rows, by="client")
    got = {r["key"]: r for r in result["rows"]}

    assert got[ledger.UNATTRIBUTED]["total_usd"] == 8.0
    assert got[ledger.UNATTRIBUTED]["instances"] == 2
    assert result["total"]["total_usd"] == 11.0
    # 帰属不明は最後に並べて目立たせる。
    assert result["rows"][-1]["key"] == ledger.UNATTRIBUTED


def test_aggregate_on_empty_ledger():
    result = ledger.aggregate({}, by="client")
    assert result["rows"] == []
    assert result["total"]["total_usd"] == 0.0


# ── annotate ─────────────────────────────────────────────────────────────────


def test_manual_attribution_survives_later_snapshots():
    rows = ledger.merge_snapshot({}, [view(1, "scratch", 3.0)], T0, ALIASES)
    rows[1]["manual_client"] = "acme"
    rows[1]["manual_purpose"] = "sweep"
    ledger._apply_attribution(rows[1], ALIASES)

    rows = ledger.merge_snapshot(rows, [view(1, "scratch", 4.0)], T1, ALIASES)

    assert rows[1]["client"] == "acme"
    assert rows[1]["purpose"] == "sweep"
    assert rows[1]["attribution_reason"] == ledger.REASON_MANUAL


def test_annotate_command_updates_the_ledger(tmp_path):
    path = tmp_path / "ledger.jsonl"
    ledger.save_ledger(path, ledger.merge_snapshot({}, [view(1, "scratch", 3.0)], T0, ALIASES))

    assert ledger.main(["annotate", "1", "--client", "acme", "--purpose", "sweep", "--ledger", str(path)]) == 0

    reloaded = ledger.load_ledger(path)
    assert reloaded[1]["client"] == "acme"
    assert reloaded[1]["purpose"] == "sweep"


def test_annotate_rejects_an_unknown_machine_id(tmp_path):
    path = tmp_path / "ledger.jsonl"
    ledger.save_ledger(path, {})
    assert ledger.main(["annotate", "999", "--client", "acme", "--ledger", str(path)]) == 1


def test_annotate_requires_at_least_one_field(tmp_path):
    path = tmp_path / "ledger.jsonl"
    ledger.save_ledger(path, ledger.merge_snapshot({}, [view(1, "scratch", 3.0)], T0, ALIASES))
    assert ledger.main(["annotate", "1", "--ledger", str(path)]) == 2


# ── 保存と読み出し ────────────────────────────────────────────────────────────


def test_save_and_load_roundtrip(tmp_path):
    path = tmp_path / "sub" / "ledger.jsonl"  # 親ディレクトリは自動で作られる
    rows = ledger.merge_snapshot({}, [view(1, "acme-a-20260720", 3.0), view(2, "globex-b-20260720", 4.0)], T0, ALIASES)
    ledger.save_ledger(path, rows)

    assert ledger.load_ledger(path) == rows


def test_load_missing_ledger_is_empty(tmp_path):
    assert ledger.load_ledger(tmp_path / "nope.jsonl") == {}


def test_report_and_list_run_on_an_empty_ledger(tmp_path, capsys):
    path = tmp_path / "ledger.jsonl"
    assert ledger.main(["report", "--ledger", str(path)]) == 0
    assert ledger.main(["list", "--ledger", str(path)]) == 0
    assert "台帳が空です" in capsys.readouterr().out


def test_state_dir_honours_xdg_state_home(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    monkeypatch.delenv("JL_LEDGER_PATH", raising=False)
    assert ledger.default_ledger_path() == tmp_path / "jl-ledger" / "ledger.jsonl"


def test_jpy_rounds_half_up_not_to_even():
    """Python 既定の round() は 1336.5 → 1336 (銀行家丸め)。台帳では四捨五入する。"""
    assert ledger._jpy(9.00, 148.5) == 1337
    assert ledger._jpy(13.00, 148.5) == 1931


def test_jpy_rate_precedence(monkeypatch):
    monkeypatch.setenv("JL_LEDGER_JPY_RATE", "150")
    assert ledger.resolve_jpy_rate(None) == 150.0
    assert ledger.resolve_jpy_rate(160.0) == 160.0  # 引数が環境変数に勝つ
    monkeypatch.delenv("JL_LEDGER_JPY_RATE")
    assert ledger.resolve_jpy_rate(None) is None  # 無ければ USD だけ出す


# ── 読み出し時の帰属の引き直し ────────────────────────────────────────────────


def test_resolve_attribution_recovers_rows_written_without_client():
    """クライアント表に後から足したクライアントの、破棄済みインスタンスも拾う。

    帰属は snapshot のときにしか付かないので、既に gone の行は二度と引き直され
    ない。読み出しのたびに引き直すことで、後からクライアント表を直せば過去分も
    集計に乗る。
    """
    rows = {
        101: {"machine_id": 101, "name": "acme-multi-stage-20260901", "cost_usd": 5.0, "status": "gone"},
        102: {"machine_id": 102, "name": "Name me", "cost_usd": 2.0, "status": "gone"},
    }
    resolved = ledger.resolve_attribution(rows, ALIASES)
    assert resolved[101]["client"] == "acme"
    assert resolved[101]["purpose"] == "multi-stage"
    assert resolved[102]["client"] == ledger.UNATTRIBUTED
    # 元の dict は書き換えない。
    assert "client" not in rows[101]


def test_resolve_attribution_keeps_manual_override():
    rows = {
        101: {
            "machine_id": 101,
            "name": "nosuchclient-train-20260814",  # 未知のクライアント
            "manual_client": "acme",
            "cost_usd": 1.0,
        }
    }
    resolved = ledger.resolve_attribution(rows, ALIASES)
    assert resolved[101]["client"] == "acme"
    assert resolved[101]["attribution_reason"] == ledger.REASON_MANUAL
