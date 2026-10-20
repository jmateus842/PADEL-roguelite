"""Wall shot sim for the padel roguelite.

Same ball model planned for Godot: position on the court (x, y) plus a fake
height z, our own gravity, bounce and wall rules, no physics engine.
Run it, look at sim/shots/*.png, tweak the tuning block, run again.
"""
import math
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection

OUT = Path(__file__).parent / "shots"

# court in meters. x goes across (0..10), y goes along (0..20)
# we play on the near half (y < 10), the opponent on the far half
W, L, NET_Y = 10.0, 20.0, 10.0
NET_H = 0.88
SERVICE_FROM_NET = 6.95

# --- tuning: these are the numbers that should carry over to godot ---
G = 9.81
DRAG = 0.02           # quadratic air drag per meter, a real padel ball is ~0.019
FLOOR_E = 0.74        # FIP-ish: dropped from 2.54m it comes back ~1.4m
FLOOR_GRIP = 0.85     # horizontal speed kept after a floor bounce
GLASS_E = 0.65        # how much of the speed into the glass comes back out
MESH_E = 0.25         # mesh eats the ball
WALL_GRIP = 0.9       # speed kept along the wall when it hits
REACH_LOW, REACH_HIGH = 0.3, 1.9   # heights a player hits comfortably
DT = 0.002
MAX_T = 5.0


def wall_at(side, y_or_x):
    """(glass height, total height) of a wall at a given point.
    back walls: 3m glass + 1m mesh. side walls step down toward the net"""
    if side == "back":
        return 3.0, 4.0
    # side walls, measured from the nearest back wall
    # ojo: the rules only say glass in the corners and mesh on the rest,
    # the 2m/2m split is the common build, not a rule
    d = min(y_or_x, L - y_or_x)
    if d < 2:
        return 3.0, 4.0
    if d < 4:
        return 2.0, 3.0
    return 0.0, 3.0


def half(y):
    return "near" if y < NET_Y else "far"


def simulate(start, vel, kick=1.0):
    """runs one shot. returns the path and the list of things that happened.
    kick: extra bounce on the first floor hit, a stand-in for topspin/flat power"""
    x, y, z = start
    vx, vy, vz = vel
    t = 0.0
    path = [(t, x, y, z)]
    events = []
    floor_hits = {"near": 0, "far": 0}
    crossed = False
    end = None

    def log(kind, detail=""):
        events.append({"t": t, "kind": kind, "x": x, "y": y, "z": z, "detail": detail})

    while t < MAX_T and end is None:
        speed = math.sqrt(vx * vx + vy * vy + vz * vz)
        vx -= DRAG * speed * vx * DT
        vy -= DRAG * speed * vy * DT
        vz -= (G + DRAG * speed * vz) * DT
        prev_y, prev_z = y, z
        x += vx * DT
        y += vy * DT
        z += vz * DT
        t += DT

        # net: interpolate the height where it crosses y = 10
        if (prev_y - NET_Y) * (y - NET_Y) < 0:
            k = (NET_Y - prev_y) / (y - prev_y)
            z_at_net = prev_z + k * (z - prev_z)
            coming_back = crossed and vy < 0
            if z_at_net < NET_H and not coming_back:
                log("net")
                end = "net"
                break
            if z_at_net < NET_H:
                # bounced off their glass and ran into the net from behind
                # still live on their side, the net just kills it
                y = 2 * NET_Y - y
                vy = -vy * 0.2
                vx *= 0.5
                log("net", "from behind")
            elif coming_back:
                log("crosses net", "back to us")
                end = "winner: came back over the net"
                break
            else:
                crossed = True
                log("crosses net", f"{z_at_net - NET_H:.2f}m over")

        if z <= 0:
            # no spin in this model, kick fakes it on the first bounce only
            e = FLOOR_E * (kick if floor_hits["far"] + floor_hits["near"] == 0 else 1.0)
            z = -z * e
            vz = -vz * e
            vx *= FLOOR_GRIP
            vy *= FLOOR_GRIP
            h = half(y)
            floor_hits[h] += 1
            log("floor", h)
            if h == "near" and not crossed:
                end = "fault: bounced on our side"
            elif h == "far" and floor_hits["far"] == 2:
                end = "winner: second bounce"
            elif vz < 0.4:
                end = "ball died"

        # walls. each one: is the ball under the top? glass or mesh?
        for axis, limit, side in (("x", 0.0, "side"), ("x", W, "side"), ("y", 0.0, "back"), ("y", L, "back")):
            pos = x if axis == "x" else y
            past = pos < limit if limit == 0.0 else pos > limit
            if not past or end:
                continue
            along = y if axis == "x" else x
            glass_h, top = wall_at(side, along)
            h = half(y)
            if z > top:
                log("over the wall", side)
                if h == "far" and floor_hits["far"] == 1:
                    end = f"winner: out over the {side} wall"
                else:
                    end = "out"
                break
            material = "glass" if z <= glass_h else "mesh"
            # rule check before bouncing it
            if h == "far" and floor_hits["far"] == 0:
                log(material, side)
                end = f"out: hit their {side} {material} before bouncing"
                break
            if h == "near" and not crossed and material == "mesh":
                log(material, side)
                end = "fault: hit our own mesh"
                break
            e = GLASS_E if material == "glass" else MESH_E
            if axis == "x":
                x = 2 * limit - x
                vx = -vx * e
                vy *= WALL_GRIP
            else:
                y = 2 * limit - y
                vy = -vy * e
                vx *= WALL_GRIP
            vz *= WALL_GRIP
            log(material, side)

        path.append((t, x, y, z))

    if end is None:
        end = "timeout"
    return path, events, end


def playable_windows(path, events):
    """stretches of time where the opponent can hit it: after the first bounce
    on their side, before the second, at a comfortable height, inside the court"""
    first = next((e["t"] for e in events if e["kind"] == "floor" and e["detail"] == "far"), None)
    if first is None:
        return []
    windows = []
    current = None
    for t, x, y, z in path:
        ok = t > first and 0 < x < W and NET_Y < y < L and REACH_LOW <= z <= REACH_HIGH
        if ok and current is None:
            current = [t, t, (x, y)]
        elif ok:
            current[1] = t
        elif current is not None:
            windows.append(current)
            current = None
    if current is not None:
        windows.append(current)
    # tiny slivers are just the ball passing through the band
    return [w for w in windows if w[1] - w[0] > 0.05]


def launch(start, speed, elevation_deg, target):
    """velocity toward a target point on the court, with an up/down angle"""
    dx, dy = target[0] - start[0], target[1] - start[1]
    flat = math.hypot(dx, dy)
    el = math.radians(elevation_deg)
    return (speed * math.cos(el) * dx / flat,
            speed * math.cos(el) * dy / flat,
            speed * math.sin(el))


# start (x, y, z), speed m/s, elevation deg, aim point (x, y), optional kick
# speeds and angles came out of a sweep, these are the versions that land in
SHOTS = {
    "drive_to_back_glass": ((5, 7, 1.0), 17, 8, (5, 20)),
    "lob": ((5, 3, 1.0), 13, 45, (5, 20)),
    "cross_to_side_glass": ((2, 8, 1.0), 17, 8, (10, 17)),
    "double_wall": ((3, 7, 1.0), 17, 8, (10, 19.5)),
    "smash_flat": ((5, 8.5, 2.7), 30, -25, (5, 20)),
    "smash_por_3": ((5, 8.5, 2.7), 30, -40, (5, 20)),
    "smash_por_4_kick": ((7, 8.5, 2.7), 30, -40, (10, 13.5), 1.6),
    "corner_kill": ((5, 8, 2.2), 14, -8, (9.6, 19.0)),
    "into_the_mesh": ((5, 8, 1.0), 11, 10, (10, 13.5)),
    "contrapared": ((5, 1.5, 0.9), 22, 32, (5, 0)),
    "too_long": ((5, 7, 1.0), 27, 6, (5, 20)),
}


def draw_court_topdown(ax):
    # horizontal axis is y (length) so the side view below lines up with it
    ax.add_patch(plt.Rectangle((0, 0), L, W, fill=True, color="#2f6f9f", alpha=0.15))
    ax.plot([NET_Y, NET_Y], [0, W], color="black", lw=2)
    for sy in (NET_Y - SERVICE_FROM_NET, NET_Y + SERVICE_FROM_NET):
        ax.plot([sy, sy], [0, W], color="white", lw=1)
    ax.plot([NET_Y - SERVICE_FROM_NET, NET_Y + SERVICE_FROM_NET], [W / 2, W / 2], color="white", lw=1)
    # walls: blue where there is glass at floor level, grey where it is mesh
    for x_edge in (0, W):
        for y0 in [i * 0.5 for i in range(40)]:
            glass_h, _ = wall_at("side", y0 + 0.25)
            ax.plot([y0, y0 + 0.5], [x_edge, x_edge], color="#3a8fd6" if glass_h else "#888888", lw=4 if glass_h else 2)
    for y_edge in (0, L):
        ax.plot([y_edge, y_edge], [0, W], color="#3a8fd6", lw=4)
    ax.set_xlim(-1.5, L + 1.5)
    ax.set_ylim(-1.5, W + 1.5)
    ax.set_xticks([0, 5, 10, 15, 20])
    ax.set_yticks([0, 5, 10])


def plot_shot(name, path, events, end, windows):
    fig, (top, side) = plt.subplots(2, 1, figsize=(11, 9), gridspec_kw={"height_ratios": [1.2, 1]}, sharex=True)
    ts = [p[0] for p in path]
    ys = [p[2] for p in path]
    xs = [p[1] for p in path]
    zs = [p[3] for p in path]

    draw_court_topdown(top)
    # shadow path on the court, colored by height
    pts = list(zip(ys, xs))
    segs = [[pts[i], pts[i + 1]] for i in range(len(pts) - 1)]
    lc = LineCollection(segs, cmap="plasma", linewidths=2.5)
    lc.set_array(zs[:-1])
    lc.set_clim(0, 4)
    top.add_collection(lc)
    # colorbar on both axes so the two views keep the same width and line up
    fig.colorbar(lc, ax=[top, side], label="height z (m)", fraction=0.025)
    top.scatter([ys[0]], [xs[0]], color="black", zorder=5, s=40)
    top.annotate("hit", (ys[0], xs[0]), textcoords="offset points", xytext=(-10, 8))

    for w in windows:
        i0 = ts.index(w[0])
        i1 = ts.index(w[1])
        top.plot(ys[i0:i1 + 1], xs[i0:i1 + 1], color="#2ca02c", lw=8, alpha=0.35, solid_capstyle="round")
        side.plot(ys[i0:i1 + 1], zs[i0:i1 + 1], color="#2ca02c", lw=8, alpha=0.35, solid_capstyle="round")

    markers = {"floor": ("o", "#d62728"), "glass": ("s", "#1f77b4"), "mesh": ("X", "#555555"),
               "net": ("v", "black"), "over the wall": ("^", "#ff7f0e")}
    n = 0
    for e in events:
        if e["kind"] not in markers:
            continue
        n += 1
        m, c = markers[e["kind"]]
        top.scatter([e["y"]], [e["x"]], marker=m, color=c, s=70, zorder=6, edgecolor="white")
        top.annotate(str(n), (e["y"], e["x"]), textcoords="offset points", xytext=(6, 6), fontsize=9, weight="bold")
        side.scatter([e["y"]], [e["z"]], marker=m, color=c, s=70, zorder=6, edgecolor="white")
        side.annotate(str(n), (e["y"], e["z"]), textcoords="offset points", xytext=(6, 6), fontsize=9, weight="bold")

    # side view: y vs height. x is flattened out, so side walls show as nothing here
    side.plot(ys, zs, color="#444444", lw=1.5)
    side.axhspan(REACH_LOW, REACH_HIGH, xmin=0, xmax=1, color="#2ca02c", alpha=0.07)
    side.plot([NET_Y, NET_Y], [0, NET_H], color="black", lw=3)
    for y_edge in (0, L):
        side.plot([y_edge, y_edge], [0, 3], color="#3a8fd6", lw=5)
        side.plot([y_edge, y_edge], [3, 4], color="#888888", lw=3)
    side.axhline(0, color="black", lw=1)
    side.set_ylim(-0.2, max(4.5, max(zs) + 0.3))
    side.set_xlabel("y: along the court (m). we are on the left, opponent on the right")
    side.set_ylabel("height z (m)")
    top.set_ylabel("x: across (m)")

    total_window = sum(w[1] - w[0] for w in windows)
    top.set_title(f"{name}  ->  {end}", loc="left", fontsize=13, weight="bold")
    side.text(0.01, 0.97, f"time to reach the far back line: {time_to_far_back(path)}\n"
                          f"opponent's hittable time: {total_window:.2f}s in {len(windows)} window(s)\n"
                          "green band = comfortable hitting height",
              transform=side.transAxes, va="top", fontsize=9,
              bbox={"facecolor": "white", "alpha": 0.8, "edgecolor": "#cccccc"})
    OUT.mkdir(exist_ok=True)
    fig.savefig(OUT / f"{name}.png", dpi=110)
    plt.close(fig)


def time_to_far_back(path):
    for t, x, y, z in path:
        if y >= L - 0.05:
            return f"{t:.2f}s"
    return "never"


def describe(events):
    parts = []
    for e in events:
        if e["kind"] == "crosses net" and e["detail"] == "back to us":
            parts.append("back over the net")
        elif e["kind"] == "crosses net":
            parts.append(f"net +{e['detail'].split('m')[0]}m")
        elif e["kind"] == "floor":
            parts.append(f"floor({e['y']:.1f})")
        elif e["kind"] in ("glass", "mesh"):
            parts.append(f"{e['detail']} {e['kind']}(z {e['z']:.1f})")
        elif e["kind"] == "over the wall":
            parts.append(f"over the {e['detail']} wall")
        elif e["kind"] == "net":
            parts.append("net from behind" if e["detail"] else "net")
    return " > ".join(parts)


def shot_row(name, start, speed, elev, target, kick=1.0):
    """runs one shot and returns (row for summary.md, path, events, end, windows)"""
    path, events, end = simulate(start, launch(start, speed, elev, target), kick)
    windows = playable_windows(path, events)
    total = sum(w[1] - w[0] for w in windows)
    row = f"| {name} | {end} | {total:.2f}s | {len(windows)} | {describe(events)} |"
    return row, path, events, end, windows


SUMMARY_HEADER = ["| shot | result | hittable time | windows | what happened |", "|---|---|---|---|---|"]


def main():
    chosen = sys.argv[1:] or list(SHOTS)
    rows = []
    for name in chosen:
        if name not in SHOTS:
            raise SystemExit(f"Don't know the shot '{name}'. Options: {', '.join(SHOTS)}")
        start, speed, elev, target, *extra = SHOTS[name]
        row, path, events, end, windows = shot_row(name, start, speed, elev, target, extra[0] if extra else 1.0)
        plot_shot(name, path, events, end, windows)
        rows.append(row)

    summary = "\n".join(SUMMARY_HEADER + rows)
    (OUT / "summary.md").write_text(summary + "\n", encoding="utf-8")
    print(summary)
    print(f"\n{len(rows)} plots in {OUT}")


# importing this file (tests do) runs nothing, running it makes the plots
if __name__ == "__main__":
    main()
