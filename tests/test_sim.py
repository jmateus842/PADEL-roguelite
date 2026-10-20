"""Python half of the tests. Run from the repo root:  python tests/test_sim.py

1. The SHOTS table in scripts/shots.gd matches the one in sim/wall_shots.py.
2. sim/shots/summary.md is up to date with the sim (no stale numbers).
3. Writes tests/golden_random.json: a few hundred random launches plus a few
   rare edge cases, run through the sim. tests/godot_tests.gd replays them in Godot and compares.

Exit code 1 if 1 or 2 fails.
"""
import ast
import json
import random
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "sim"))
import wall_shots as sim  # noqa: E402

GOLDEN = ROOT / "tests" / "golden_random.json"
RANDOM_COUNT = 400
PER_OUTCOME = 60   # cap per outcome, so easy faults don't crowd out the rare rules
SEED = 1969   # padel's birth year, any fixed number works

# rare rules the random set doesn't reach, found by a wider search.
# start, speed, elevation, target, kick
EDGE_CASES = {
    "e_came_back_over_net": ([6.687, 9.641, 2.101], 28.364, -9.883, [4.816, 16.109], 1.524),
    "e_net_from_behind": ([2.92, 4.122, 2.657], 33.549, -4.598, [5.314, 12.578], 1.177),
    "e_timeout": ([8.938, 4.115, 1.377], 15.056, 71.781, [8.397, 10.512], 1.622),
}

failures = []


def check(ok, message):
    print(("  ok  " if ok else "FAIL  ") + message)
    if not ok:
        failures.append(message)


def gd_shots():
    """reads const SHOTS from shots.gd. a GDScript dict of lists is also a Python literal"""
    text = (ROOT / "scripts" / "shots.gd").read_text(encoding="utf-8")
    start = text.index("const SHOTS := ") + len("const SHOTS := ")
    end = text.index("\n}", start) + 2
    return ast.literal_eval(text[start:end])


def py_shots():
    """the sim's table in the same shape as shots.gd: lists, floats, kick always present"""
    out = {}
    for name, (start, speed, elev, target, *extra) in sim.SHOTS.items():
        out[name] = [[float(v) for v in start], float(speed), float(elev),
                     [float(v) for v in target], float(extra[0] if extra else 1.0)]
    return out


def test_tables_match():
    print("SHOTS table: shots.gd vs wall_shots.py")
    gd, py = gd_shots(), py_shots()
    check(list(gd) == list(py), f"same shots in the same order ({len(py)})")
    for name in py:
        if name in gd:
            check(gd[name] == py[name], f"{name} launch values match")


def test_summary_fresh():
    print("sim/shots/summary.md is current")
    lines = (ROOT / "sim" / "shots" / "summary.md").read_text(encoding="utf-8").splitlines()
    rows = {l.split("|")[1].strip(): l.strip() for l in lines[2:] if l.count("|") > 2}
    for name, (start, speed, elev, target, *extra) in sim.SHOTS.items():
        row = sim.shot_row(name, start, speed, elev, target, extra[0] if extra else 1.0)[0]
        check(rows.get(name) == row, f"{name} row is current")
    if failures:
        print("      rerun: python sim/wall_shots.py")


def random_launch(rng):
    start = [round(rng.uniform(0.5, 9.5), 3), round(rng.uniform(0.5, 9.5), 3), round(rng.uniform(0.3, 2.9), 3)]
    while True:
        # most shots go toward their side, some into our own glass (contrapared)
        target = [round(rng.uniform(0.0, 10.0), 3),
                  round(rng.uniform(10.5, 20.0) if rng.random() < 0.85 else rng.uniform(0.0, start[1] - 0.5), 3)]
        if abs(target[0] - start[0]) + abs(target[1] - start[1]) > 0.5:
            break
    speed = round(rng.uniform(4.0, 32.0), 3)
    elev = round(rng.uniform(-45.0, 65.0), 3)
    kick = 1.0 if rng.random() < 0.8 else round(rng.uniform(1.0, 1.8), 3)
    return start, speed, elev, target, kick


def write_golden():
    print(f"random launches -> {GOLDEN.relative_to(ROOT)}")
    rng = random.Random(SEED)
    cases = []
    seen = Counter()
    tries = 0
    while len(cases) < RANDOM_COUNT and tries < RANDOM_COUNT * 50:
        tries += 1
        start, speed, elev, target, kick = random_launch(rng)
        name = f"r{len(cases):03d}"
        row, path, events, end, _ = sim.shot_row(name, start, speed, elev, target, kick)
        if seen[end] >= PER_OUTCOME:
            continue
        seen[end] += 1
        t, x, y, z = path[-1]
        cases.append({"name": name, "start": start, "speed": speed, "elev": elev, "target": target,
                      "kick": kick, "row": row, "steps": len(path), "events": len(events),
                      "final": [t, x, y, z]})
    for name, launch_values in EDGE_CASES.items():
        start, speed, elev, target, kick = launch_values
        row, path, events, end, _ = sim.shot_row(name, start, speed, elev, target, kick)
        t, x, y, z = path[-1]
        cases.append({"name": name, "start": start, "speed": speed, "elev": elev, "target": target,
                      "kick": kick, "row": row, "steps": len(path), "events": len(events),
                      "final": [t, x, y, z]})
    GOLDEN.write_text(json.dumps({"seed": SEED, "cases": cases}, indent=1) + "\n", encoding="utf-8")
    ends = Counter(c["row"].split("|")[2].strip() for c in cases)
    print(f"  wrote {len(cases)} cases. outcomes covered:")
    for end, n in ends.most_common():
        print(f"      {n:4d}  {end}")
    check(len(ends) >= 13, f"cases hit at least 13 different outcomes ({len(ends)})")
    check(any("net from behind" in c["row"] for c in cases), "a case hits the net from behind")


if __name__ == "__main__":
    test_tables_match()
    test_summary_fresh()
    write_golden()
    print(f"\nPython: {'all good' if not failures else f'{len(failures)} failed'}")
    sys.exit(1 if failures else 0)
