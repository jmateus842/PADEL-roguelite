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
