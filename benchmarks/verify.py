"""Cross-check completed game reports, source CRCs, and README table values."""
import json
from pathlib import Path
import zlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "benchmarks/2026-10-08"
readme = (ROOT / "README.md").read_text(encoding="utf-8")
reports = {}
for realm in ("server", "client"):
    report = json.loads((RESULTS / f"{realm}.json").read_text(encoding="utf-8"))
    assert report["completed"] and report["realm"] == realm
    assert len(report["rows"]) == 22
    assert all(check["passed"] for check in report["compatibility"])
    assert len(report["workload"]["phases"]) == 6
    for phase in report["workload"]["phases"]:
        assert phase["interval"]["count"] >= 30
        assert phase["cpu"]["count"] == phase["interval"]["count"]
        assert phase["menu_frames"] == 0
    for row in report["rows"]:
        for side in ("stock", "fast"):
            samples = row[side]["samples"]
            assert len(samples) == 9 and all(value > 0 for value in samples)
            assert sorted(samples)[4] == row[side]["median"]
        expected = row["stock"]["median"] / row["fast"]["median"]
        assert abs(row["ratio"] - expected) < 1e-10
    # Historical reports retain the measured revision before the rename.
    paths = {name: f"glibus/lua/libs/{name}.lua" for name in ("hook", "math", "vector", "color")}
    paths["loader"] = "glibus/lua/autorun/libs_init.lua"
    paths["benchmark"] = "lua/fastpath/benchmark.lua"
    for name, path in paths.items():
        source = subprocess.check_output(["git", "show", f"5f7e7a1:{path}"], cwd=ROOT)
        # Git normalizes CRLF; the engine hashed the original worktree bytes.
        crlf = source.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        assert str(report["hashes"][name]) in {str(zlib.crc32(source)), str(zlib.crc32(crlf))}, name
    for name in ("hook", "math", "vector", "color"):
        assert str(zlib.crc32((ROOT / f"fastpath/lua/libs/{name}.lua").read_bytes())) == str(report["hashes"][name]), name
    reports[realm] = report

client_rows = {row["name"]: row for row in reports["client"]["rows"]}
for row in reports["server"]["rows"]:
    if row["name"] in ("loop control", "hook.Call 0"):
        continue
    other = client_rows[row["name"]]
    values = [row["ratio"], other["ratio"]]
    expected = "| " + row["name"] + " | " + " | ".join(f"{value:.2f}" for value in values) + " |"
    assert expected in readme, row["name"]

def average(report, mode, metric):
    phases = [phase[metric] for phase in report["workload"]["phases"] if phase["mode"] == mode]
    return sum(phase["mean_ms"] * phase["count"] for phase in phases) / sum(phase["count"] for phase in phases)

stock_fps = 1000 / average(reports["client"], "stock", "interval")
fast_fps = 1000 / average(reports["client"], "fast", "interval")
stock_cpu = average(reports["server"], "stock", "cpu")
fast_cpu = average(reports["server"], "fast", "cpu")
assert f"| Средний FPS | {stock_fps:.2f} | {fast_fps:.2f} | +{(fast_fps / stock_fps - 1) * 100:.1f}% |" in readme
assert f"| Время тестовой Lua-нагрузки, мс/тик | {stock_cpu:.2f} | {fast_cpu:.2f} | −{(1 - fast_cpu / stock_cpu) * 100:.1f}% |" in readme

assert reports["client"]["workload"]["cvars"]["fps_max_nofocus"] == "300"
assert reports["client"]["workload"]["resolution"] == [1280, 720]
for realm in ("server", "client"):
    before = json.loads((ROOT / f"benchmarks/2026-10-08-before-fixes/{realm}.json").read_text(encoding="utf-8"))
    failed = {check["name"] for check in before["compatibility"] if not check["passed"]}
    assert "loader migration and repeat inclusion" in failed
    assert "Color false alpha stock compatibility" in failed
assert not (ROOT / "benchmarks/RUN_ONCE").exists()
assert readme.count("<!-- FASTPATH_BENCH_START -->") == 1
assert "## Credits" in readme and "Srlion" in readme and "trojanhoes" in readme
assert "Intel" not in readme and "GTX" not in readme
assert not (ROOT / "glibus").exists()
assert "addons/garrysmod-fastpath/fastpath/lua/" in (ROOT / "lua/fastpath/benchmark.lua").read_text(encoding="utf-8")
print("Verified: 44 benchmark rows, 8 passing runtime checks, 12 workload phases, source CRCs, README numbers, pre-fix failures, opt-in removed.")
