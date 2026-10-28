extends RefCounted
## Plans a shot's launch velocity: you, the opponent and the practice court
## all hit through here. Works in model coordinates, so the hitter is always on
## the near half aiming at the far half. A far-side hitter flips its contact
## point first (x to W - x, y to L - y), the same trick ball.gd uses to draw.
##
## Two shots:
##   plan()      flat drive. Lowest angle that clears the net, raised until it
##               lands at the target depth, softer when it would fly long
##   plan_lob()  high ball at a fixed angle, pace picked so it lands deep
##
## The planner runs its own light copy of the ball's flight (drag, gravity,
## net) at a coarser step. If you retune ball_model.gd, rerun the tests: the
## return grids in suites 7 and 8 catch a planner that drifted.

const BallModel := preload("res://scripts/ball_model.gd")

# --- drive ---
## base pace, m/s. Drops when that would fly long
const RETURN_SPEED := 16.0
const MIN_SPEED := 7.0
## where the drive aims to land, meters from the hitter's back wall
const TARGET_DEPTH := 16.5
## stick left/right at contact moves the aim this far from the center line, m
const AIM_SPREAD := 4.0
## aim stick shorter than this counts as resting, the sideways nudge applies
const AIM_REST := 0.3
## aim stick pointing back past this (court y of the stick, -1 is straight back)
## means "play it off my own back glass"
const BACK_WEDGE := -0.5
## you can only play the contrapared this close to your back glass, m
const CONTRA_MAX_Y := 3.0
## where the contrapared aims to land on their half, m from your back glass
const CONTRA_DEPTH := 15.0
## paces and angles the contrapared tries, most likely first: [m/s, [degrees]]
const CONTRA_TRIES := [[20.0, [24.0, 32.0, 40.0]], [16.0, [36.0, 44.0, 52.0]], [24.0, [12.0, 18.0, 24.0]]]
## target zones. The aim stick picks a zone by its angle: straight ahead for a
## drive (0 degrees), straight back for a contrapared. Each entry is
## [angle, where it lands (court m), pace m/s]. Short angles are slower so they
## can land short of the usual depth. Guesses, tuned by the zone grid test
const DRIVE_ZONES := [
	[-75.0, Vector2(1.5, 12.0), 11.0],
	[-35.0, Vector2(1.5, TARGET_DEPTH), RETURN_SPEED],
	[0.0, Vector2(5.0, TARGET_DEPTH), RETURN_SPEED],
	[35.0, Vector2(8.5, TARGET_DEPTH), RETURN_SPEED],
	[75.0, Vector2(8.5, 12.0), 11.0],
]
const CONTRA_ZONES := [
	[-35.0, Vector2(2.0, CONTRA_DEPTH), RETURN_SPEED],
	[0.0, Vector2(5.0, CONTRA_DEPTH), RETURN_SPEED],
	[35.0, Vector2(8.0, CONTRA_DEPTH), RETURN_SPEED],
]
## the target stays locked on a zone while the stick is within this many
## degrees of its angle, then slides to the next zone. The lock is what stops it
## flickering between two zones
const ZONE_LOCK := 12.0
## the drive wants at least this much air over the net, m
const NET_CLEAR := 0.15
## the first bounce has to land this far inside the walls, m
const WALL_MARGIN := 0.4

# --- lob ---
## launch angle, degrees. High enough to clear a player at the net
const LOB_ELEV := 52.0
## where the lob lands, meters from the hitter's back wall (2 m from theirs)
const LOB_DEPTH := 18.0
const LOB_MIN_SPEED := 5.0
const LOB_MAX_SPEED := 25.0

## planner step. Coarser than the model on purpose: it runs ~20 flights per hit
const PLAN_DT := 0.01


## where a drive aims sideways for a stick reading of -1 to 1, court x in m.
## The shot and the aim line on screen both read this
static func aim_x(stick: float) -> float:
	return 5.0 + clampf(stick, -1.0, 1.0) * AIM_SPREAD


## what a swing does for the aim stick. dir is the stick in court axes (x right,
## y toward their half, length 0 to 1), nudge is the left stick x, near_x and
## near_y are where you stand. The match and the aim arrow both read this, so
## they can't disagree. Returns {kind: "drive" or "contra", x, to, land}:
## x is the sideways spot the shot is aimed to land at, to is the spot the arrow
## points at (their half for a drive, your glass for a contrapared), land is
## where the ball should come down on their half (court m)
static func aim_choice(near_x: float, near_y: float, nudge: float, dir: Vector2) -> Dictionary:
	if dir.length() < AIM_REST:
		var rest := Vector2(aim_x(nudge), TARGET_DEPTH)
		return {"kind": "drive", "x": rest.x, "to": rest, "land": rest, "pace": RETURN_SPEED}
	if dir.y < BACK_WEDGE and near_y <= CONTRA_MAX_Y:
		var z := zone_target(rad_to_deg(atan2(dir.x, -dir.y)), CONTRA_ZONES)
		var land: Vector2 = z[0]
		return {"kind": "contra", "x": land.x, "to": Vector2(contra_glass_x(near_x, near_y, land.x), 0.0), "land": land, "pace": z[1]}
	# a back push with no glass in reach counts as a forward push at the same sideways angle
	var d := zone_target(rad_to_deg(atan2(dir.x, absf(dir.y))), DRIVE_ZONES)
	var spot: Vector2 = d[0]
	return {"kind": "drive", "x": spot.x, "to": spot, "land": spot, "pace": d[1]}


## a drive to a zone spot at the zone's pace. A slow pace can't always clear the
## net from far back, then it goes at the normal pace instead and lands deeper
static func plan_to(contact: Array, spot: Vector2, pace: float) -> Array:
	var vel := plan(contact, spot.x, spot.y, pace)
	if pace < RETURN_SPEED and _landing(contact, vel) < 0.0:
		vel = plan(contact, spot.x, spot.y)
	return vel


## the target for a stick angle (degrees) among zones: [spot, pace]. Locked on a
## zone within ZONE_LOCK of its angle, a straight slide between two locks,
## clamped past the outer zones. Continuous, so the target (and its glow on
## screen) moves smoothly instead of jumping
static func zone_target(angle: float, zones: Array) -> Array:
	var a := clampf(angle, zones[0][0], zones[zones.size() - 1][0])
	for i in zones.size():
		if absf(a - zones[i][0]) <= ZONE_LOCK:
			return [zones[i][1], zones[i][2]]
	for i in zones.size() - 1:
		var lo: float = zones[i][0] + ZONE_LOCK
		var hi: float = zones[i + 1][0] - ZONE_LOCK
		if a > lo and a < hi:
			var t := (a - lo) / (hi - lo)
			return [zones[i][1].lerp(zones[i + 1][1], t), lerpf(zones[i][2], zones[i + 1][2], t)]
	return [zones[zones.size() - 1][1], zones[zones.size() - 1][2]]


## how much of a sideways offset at the glass is left on their half. The ball
## keeps its sideways speed through the rebound but loses forward speed, so a
## small offset at the glass is a big one by the time it lands
static func _glass_ratio(near_y: float) -> float:
	var y := maxf(near_y, 0.5)
	return y / (y + 1.4 * CONTRA_DEPTH)


## where on your back glass (court x, m) to hit so the ball comes down near
## target_x on their half. A first guess, plan_contrapared refines it
static func contra_glass_x(near_x: float, near_y: float, target_x: float) -> float:
	return clampf(near_x + (target_x - near_x) * _glass_ratio(near_y), 0.3, BallModel.W - 0.3)


## velocity for a contrapared: hit your own back glass so it rebounds over the net
## and lands on their half near target_x. Tries a few paces and angles with the
## real ball model, keeps the one that lands closest to CONTRA_DEPTH, then nudges
## the glass spot to fix the sideways landing. Returns [] when nothing works from
## this contact (too high, too far out)
static func plan_contrapared(contact: Array, target_x: float) -> Array:
	var ratio := _glass_ratio(contact[1])
	var glass_x := contra_glass_x(contact[0], contact[1], target_x)
	var best_speed := 0.0
	var best_el := 0.0
	var best_land := Vector2(-1.0, -1.0)
	var best_gap := INF
	# each flight costs a few ms, so try the likely pace first and only go on to
	# the others when none of its angles work
	for group in CONTRA_TRIES:
		var speed: float = group[0]
		for el in group[1]:
			var land := _contra_landing(contact, BallModel.launch(contact, speed, el, [glass_x, 0.0]))
			if land.y < 0.0:
				continue
			var gap := absf(land.y - CONTRA_DEPTH)
			if gap < best_gap:
				best_gap = gap
				best_speed = speed
				best_el = el
				best_land = land
		if best_land.y >= 0.0:
			break
	if best_land.y < 0.0:
		return []
	var best := BallModel.launch(contact, best_speed, best_el, [glass_x, 0.0])
	for i in 2:
		# the glass spot moves the landing sideways by about 1 / ratio per m
		var try_x := clampf(glass_x + (target_x - best_land.x) * ratio, 0.3, BallModel.W - 0.3)
		var vel := BallModel.launch(contact, best_speed, best_el, [try_x, 0.0])
		var land := _contra_landing(contact, vel)
		if land.y < 0.0:
			break
		if absf(land.x - target_x) < absf(best_land.x - target_x):
			glass_x = try_x
			best = vel
			best_land = land
	return best


## the real model's first floor contact on their half as (x, y), or (-1, -1)
## when the ball doesn't hit our glass first, hits our mesh, or never gets there
static func _contra_landing(contact: Array, vel: Array) -> Vector2:
	var m = BallModel.new()
	m.reset(contact, vel, 1.0)
	var seen := 0
	while not m.is_done():
		m.step()
		while seen < m.events.size():
			var e: Dictionary = m.events[seen]
			seen += 1
			if e.kind == "glass" and seen == 1 and e.detail == "back":
				continue
			if e.kind == "crosses net" and e.detail != "back to us":
				continue
			if e.kind == "floor" and e.detail == "far":
				# in the box with a margin, and the first wall it touched was our glass
				if e.y < BallModel.NET_Y + 1.0 or e.y > BallModel.L - WALL_MARGIN 						or e.x < WALL_MARGIN or e.x > BallModel.W - WALL_MARGIN:
					return Vector2(-1.0, -1.0)
				return Vector2(e.x, e.y)
			return Vector2(-1.0, -1.0)
	return Vector2(-1.0, -1.0)


## velocity for a drive from contact [x, y, z] that clears the net and lands
## near (aim_x, depth). Lowest angle that clears, then deeper if needed.
## A ball that can't stay in at full pace gets a softer, higher shot
static func plan(contact: Array, aim_x: float, depth := TARGET_DEPTH, speed := RETURN_SPEED) -> Array:
	var target := [aim_x, depth]
	var el := 0.0
	while true:
		el = _lowest_clearing(contact, speed, target)
		var land := _landing(contact, BallModel.launch(contact, speed, el, target))
		if land < 0.0:
			break   # nothing clears from here
		if land < depth and el < 45.0:
			# clears with room to spare: raise it until it lands at the target
			var lo := el
			var hi := 45.0
			for i in 12:
				var mid := (lo + hi) * 0.5
				if _landing(contact, BallModel.launch(contact, speed, mid, target)) < depth:
					lo = mid
				else:
					hi = mid
			el = hi
			break
		if land <= BallModel.L - WALL_MARGIN or speed <= MIN_SPEED:
			break
		speed = maxf(speed * 0.8, MIN_SPEED)
	return BallModel.launch(contact, speed, el, target)


## velocity for a lob from contact [x, y, z] landing near (aim_x, depth)
static func plan_lob(contact: Array, aim_x: float, depth := LOB_DEPTH) -> Array:
	var target := [aim_x, depth]
	var lo := LOB_MIN_SPEED
	var hi := LOB_MAX_SPEED
	for i in 14:
		var mid := (lo + hi) * 0.5
		var land := _landing(contact, BallModel.launch(contact, mid, LOB_ELEV, target))
		if land >= 0.0 and land >= depth:
			hi = mid
		else:
			lo = mid   # short or into the net: more pace
	return BallModel.launch(contact, hi, LOB_ELEV, target)


## smallest elevation, -10 to 85 deg, that clears the net by NET_CLEAR
static func _lowest_clearing(contact: Array, speed: float, target: Array) -> float:
	var lo := -10.0
	var hi := 85.0
	if _clears(contact, BallModel.launch(contact, speed, lo, target)):
		return lo
	for i in 12:
		var mid := (lo + hi) * 0.5
		if _clears(contact, BallModel.launch(contact, speed, mid, target)):
			hi = mid
		else:
			lo = mid
	return hi


static func _clears(c: Array, v: Array) -> bool:
	return _fly(c, v, true) > 0.0


## y where the planned ball first lands, -1 if it hits the net or lands short,
## 99 if it reaches a wall first (long or wide)
static func _landing(c: Array, v: Array) -> float:
	return _fly(c, v, false)


## light copy of the model's flight: drag, gravity, net. Walls only count as
## "too far", it stops at the first bounce. stop_at_net: return 1 once it's over
static func _fly(c: Array, v: Array, stop_at_net: bool) -> float:
	var x: float = c[0]
	var y: float = c[1]
	var z: float = c[2]
	var vx: float = v[0]
	var vy: float = v[1]
	var vz: float = v[2]
	var t := 0.0
	while t < 4.0:
		var s := sqrt(vx * vx + vy * vy + vz * vz)
		vx -= BallModel.DRAG * s * vx * PLAN_DT
		vy -= BallModel.DRAG * s * vy * PLAN_DT
		vz -= (BallModel.G + BallModel.DRAG * s * vz) * PLAN_DT
		var py := y
		var pz := z
		x += vx * PLAN_DT
		y += vy * PLAN_DT
		z += vz * PLAN_DT
		t += PLAN_DT
		if py < BallModel.NET_Y and y >= BallModel.NET_Y:
			var k := (BallModel.NET_Y - py) / (y - py)
			if pz + k * (z - pz) < BallModel.NET_H + NET_CLEAR:
				return -1.0
			if stop_at_net:
				return 1.0
		if x < 0.0 or x > BallModel.W or y > BallModel.L:
			return -1.0 if y < BallModel.NET_Y else 99.0
		if z <= 0.0:
			if y <= BallModel.NET_Y:
				return -1.0
			var wide := x < WALL_MARGIN or x > BallModel.W - WALL_MARGIN or y > BallModel.L - WALL_MARGIN
			return 99.0 if wide else y
	return 99.0
