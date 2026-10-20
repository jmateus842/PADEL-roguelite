extends RefCounted
## A basic opponent: a brain that drives one player body. Usually the far half,
## but it works on either side (tests and demo mode put one on yours too).
##
## Each tick:
##   ball coming my way  wait REACTION, then step a copy of the ball ahead and
##                       pick the first spot where it's in my band and I can
##                       get there without a scramble. Run there. Swing the moment the
##                       ball is in reach.
##   otherwise           walk back to the home spot near my back glass.
##
## Misses: once per ball it rolls a whiff, likelier when it had to run hard.
## Shot choice: drive away from you. If you stand close to the net, lob over you.
## That makes standing at the net cost something, which the volley vs. bounce
## question from Session 8 needs.
##
## Difficulty knobs are the constants below. All randomness goes through a
## seeded generator, so the same seed plays the same match.

const BallModel := preload("res://scripts/ball_model.gd")
const Planner := preload("res://scripts/shot_planner.gd")

# --- difficulty ---
## seconds of ball flight before it starts to react
const REACTION := 0.25
## top running speed, m/s. You run at player.gd SPEED (5.5)
const RUN_SPEED := 5.0
## pace of its drives, m/s
const DRIVE_SPEED := 15.0
## random error on where it aims, meters left or right
const AIM_ERROR := 0.8
## lob when you stand within this many meters of the net
const LOB_WHEN := 3.5
## how far off the center line it aims its drives, m
const AIM_WIDE := 3.0
## chance it whiffs a ball: MISS_BASE on an easy ball, plus MISS_PRESSURE
## times strain². Pressure is run time over the time it had, 0 to 1. Strain
## counts only the pressure above STRAIN_FROM, scaled back to 0 to 1, because
## pressure sits near 0.6 even on routine balls (Session 13)
const MISS_BASE := 0.03
const MISS_PRESSURE := 0.5
const STRAIN_FROM := 0.4

# --- positioning ---
## where it waits between shots, meters from its own back wall
const HOME_DEPTH := 2.5
## extra time it wants in hand before it commits to a spot, s
const SLACK := 0.05
## it takes the first spot it reaches with pressure at or under this. If there's
## none, the spot with the least pressure (often waiting for the bounce or glass)
const COMFORT := 0.6

var rules   # match_rules.gd
var side := "far"
var body    # player.gd
var rng := RandomNumberGenerator.new()

## the plan for the ball in the air: which shot it belongs to and where to stand
var plan_id := -1
var stand := Vector2.ZERO
var plan_t := 0.0
var reachable := false
## 0 when it had all the time in the world, 1 when it barely made it
var pressure := 0.0
## pressure above STRAIN_FROM, 0 to 1. Drives the miss chance and the ring
## under it in the match overlay
var strain := 0.0
## rolled once per ball: this one it will let through
var whiff := false
var last_was_lob := false
var whiffs := 0


func _init(rules_obj, my_side := "far", seed := 1969) -> void:
	rules = rules_obj
	side = my_side
	body = rules.bodies[side]
	body.top_speed = RUN_SPEED
	rng.seed = seed
	rules.brains[side] = self


func home() -> Vector2:
	var y := BallModel.L - HOME_DEPTH if side == "far" else HOME_DEPTH
	return Vector2(5.0, y)


func tick(delta: float) -> void:
	var target := home()
	if rules.state == "serve":
		return   # everyone holds still for the serve
	var ball = rules.ball
	if rules.receiver() == side and not ball.model.is_done():
		if plan_id != rules.shot_id:
			if ball.model.t < REACTION:
				target = body.pos()   # hasn't read the shot yet
			else:
				make_plan()
				strain = clampf((pressure - STRAIN_FROM) / (1.0 - STRAIN_FROM), 0.0, 1.0)
				whiff = rng.randf() < MISS_BASE + MISS_PRESSURE * strain * strain
				if whiff:
					whiffs += 1
		if plan_id == rules.shot_id:
			target = stand
		if rules.in_reach(side) and not whiff:
			body.start_swing()
	_walk_to(target, delta)


func _walk_to(target: Vector2, delta: float) -> void:
	var to: Vector2 = target - body.pos()
	var d: float = to.length()
	# slow down on arrival so it doesn't overshoot and wobble
	var dir: Vector2 = Vector2.ZERO if d < 0.02 else to / d * clampf(d * 4.0 / body.top_speed, 0.0, 1.0)
	body.drive(dir, delta)


## seconds to run d meters from a standstill
func run_time(d: float) -> float:
	if d < 0.05:
		return 0.0
	return d / body.top_speed + body.top_speed / (2.0 * body.ACCEL)


## step a copy of the ball ahead, pick the first spot it can make in time
func make_plan() -> void:
	var ball = rules.ball
	var sim = ball.model.clone()
	var now: float = sim.t
	var best_gap := INF
	plan_id = rules.shot_id
	reachable = false
	pressure = 1.0
	var lo: Vector2 = body.bounds_lo()
	var hi: Vector2 = body.bounds_hi()
	var n := 0
	while not sim.is_done():
		sim.step()
		n += 1
		if n % 5 != 0 or not sim.crossed() or sim.is_done():
			continue
		if sim.z < body.BAND_LOW or sim.z > body.BAND_HIGH:
			continue
		var b: Vector2 = ball.world(sim.x, sim.y)
		# stand where the ball's shadow will be, kept inside my area
		var spot := b.clamp(lo, hi)
		if spot.distance_to(b) > body.REACH * 0.8:
			continue   # too close to a wall to reach from inside the court
		var need := run_time(body.pos().distance_to(spot))
		var have: float = sim.t - now
		var gap: float = need - (have - SLACK)
		if gap <= 0.0:
			var p := clampf(need / maxf(have, 0.01), 0.0, 1.0)
			if not reachable or p < pressure:
				pressure = p
				stand = spot
				plan_t = sim.t
				reachable = true
			if p <= COMFORT:
				return   # earliest spot it can reach without a scramble
		elif not reachable and gap < best_gap:
			# can't make it (yet): run for the spot it misses by the least
			best_gap = gap
			stand = spot
			plan_t = sim.t


## velocity for its shot from contact (model coordinates, so it's on the near half)
func choose_shot(contact: Array) -> Array:
	var you: Vector2 = rules.bodies[rules.other(side)].pos()
	var you_m := Vector2(BallModel.W - you.x, BallModel.L - you.y) if side == "far" else you
	last_was_lob = you_m.y < BallModel.NET_Y + LOB_WHEN
	# aim at the side you aren't on, or a random side when you're central
	var away := -signf(you_m.x - 5.0)
	if absf(you_m.x - 5.0) < 0.5:
		away = 1.0 if rng.randf() < 0.5 else -1.0
	# a rushed shot sprays more
	var err := AIM_ERROR * (1.0 + pressure)
	var aim_x := clampf(5.0 + away * AIM_WIDE + rng.randf_range(-err, err), 1.0, 9.0)
	if last_was_lob:
		return Planner.plan_lob(contact, aim_x)
	return Planner.plan(contact, aim_x, Planner.TARGET_DEPTH, DRIVE_SPEED)
