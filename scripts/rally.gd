extends RefCounted
## Practice rally rules: a feeder on the far half sends one of the sim's shots,
## the player returns it. No opponent yet, so a point ends when the return lands.
## Plain object on top of a ball node and a player node, so tests can run it
## without a scene.
##
## Feeds play the sim's SHOTS flipped (ball.gd draws them turned around), so the
## feeder stands where the sim's hitter stands, mirrored onto the far half.

const BallModel := preload("res://scripts/ball_model.gd")
const Shots := preload("res://scripts/shots.gd")

## every sim shot except the smashes that leave the court: nothing to return there
const FEEDS := [
	"drive_to_back_glass", "lob", "cross_to_side_glass", "double_wall",
	"corner_kill", "into_the_mesh", "contrapared", "smash_flat", "too_long",
]

# --- the return shot ---
## base pace of a return, m/s. Drops when that would fly long
const RETURN_SPEED := 16.0
const MIN_SPEED := 7.0
## where the return aims to land, meters from our back wall
const TARGET_DEPTH := 16.5
## stick left/right at contact moves the aim this far from the center line, m
const AIM_SPREAD := 4.0
## the planner wants at least this much air over the net, m
const NET_CLEAR := 0.15
## the first bounce has to land this far inside the walls, m
const WALL_MARGIN := 0.4
## planner step. Coarser than the model on purpose: it runs ~20 flights per hit
const PLAN_DT := 0.01

var ball   # ball.gd
var player # player.gd
## "feed": ball coming at the player. "return": player's ball going away. "idle": between points
var state := "idle"
var feed_name := ""
## stick x at the moment of the hit, -1 to 1. practice.gd sets it every tick
var aim := 0.0
## what happened last point, for the HUD
var last := ""

var fed := 0
var returned := 0
var returns_in := 0
var return_errors := 0
var missed := 0
var good_leaves := 0


func _init(ball_node, player_node) -> void:
	ball = ball_node
	player = player_node
	ball.hit_check = try_hit
	ball.point_over.connect(on_point_over)


func feed(shot_name: String) -> void:
	var s: Array = Shots.SHOTS[shot_name]
	ball.play(s[0], BallModel.launch(s[0], s[1], s[2], s[3]), s[4], true)
	feed_name = shot_name
	state = "feed"
	fed += 1


## the ball's true court position (the shadow) and height
func ball_court() -> Vector3:
	var w: Vector2 = ball.world(ball.model.x, ball.model.y)
	return Vector3(w.x, w.y, ball.model.z)


## padel rules for the receiver: the feed is alive and has crossed to our side.
## Volleys count, so no bounce is needed
func ball_playable() -> bool:
	return state == "feed" and not ball.model.is_done() and ball.model.crossed()


func in_reach() -> bool:
	if not ball_playable():
		return false
	var b := ball_court()
	return player.can_reach(b.x, b.y, b.z)


## ball.gd calls this after every model step
func try_hit() -> bool:
	if not player.is_swinging() or not in_reach():
		return false
	var b := ball_court()
	var contact := [b.x, b.y, b.z]
	var aim_x := 5.0 + clampf(aim, -1.0, 1.0) * AIM_SPREAD
	var shot := plan_return(contact, aim_x)
	player.used_swing()
	ball.play(contact, shot, 1.0, false)
	state = "return"
	returned += 1
	return true


func on_point_over(result: String) -> void:
	if state == "feed":
		# the feed's own result, seen from the feeder
		if result.begins_with("winner"):
			missed += 1
			last = "Missed (%s)" % feed_name
		else:
			good_leaves += 1
			last = "Feed went out, good leave (%s)" % result
	elif state == "return":
		if result.begins_with("winner"):
			returns_in += 1
			last = "Return in (%s)" % result
		else:
			return_errors += 1
			last = "Return error (%s)" % result
	state = "idle"


## velocity for a return from contact [x, y, z] that clears the net and lands
## near (aim_x, TARGET_DEPTH). Lowest angle that clears, then deeper if needed.
## A ball that can't stay in at full pace gets a softer, higher shot
static func plan_return(contact: Array, aim_x: float) -> Array:
	var target := [aim_x, TARGET_DEPTH]
	var speed := RETURN_SPEED
	var el := 0.0
	while true:
		el = _lowest_clearing(contact, speed, target)
		var land := _landing(contact, BallModel.launch(contact, speed, el, target))
		if land < 0.0:
			break   # nothing clears from here
		if land < TARGET_DEPTH and el < 45.0:
			# clears with room to spare: raise it until it lands at the target
			var lo := el
			var hi := 45.0
			for i in 12:
				var mid := (lo + hi) * 0.5
				if _landing(contact, BallModel.launch(contact, speed, mid, target)) < TARGET_DEPTH:
					lo = mid
				else:
					hi = mid
			el = hi
			break
		if land <= BallModel.L - WALL_MARGIN or speed <= MIN_SPEED:
			break
		speed = maxf(speed * 0.8, MIN_SPEED)
	return BallModel.launch(contact, speed, el, target)


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
