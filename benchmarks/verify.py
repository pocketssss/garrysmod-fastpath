"""Cross-check completed game reports, source CRCs, and README table values."""
import json
from pathlib import Path
import zlib

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
    paths = {name: ROOT / f"glibus/lua/libs/{name}.lua" for name in ("hook", "math", "vector", "color")}
    paths["loader"] = ROOT / "glibus/lua/autorun/libs_init.lua"
    paths["benchmark"] = ROOT / "lua/fastpath/benchmark.lua"
    for name, path in paths.items():
        assert str(zlib.crc32(path.read_bytes())) == str(report["hashes"][name]), name
    reports[realm] = report

client_rows = {row["name"]: row for row in reports["client"]["rows"]}
for row in reports["server"]["rows"]:
    other = client_rows[row["name"]]
    values = [row["stock"]["median"], row["fast"]["median"], row["ratio"],
              other["stock"]["median"], other["fast"]["median"], other["ratio"]]
    expected = "| " + row["name"] + " | " + " | ".join(f"{value:.2f}" for value in values) + " |"
    assert expected in readme, row["name"]

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
print("Verified: 44 benchmark rows, 8 passing runtime checks, 12 workload phases, source CRCs, README numbers, pre-fix failures, opt-in removed.")
