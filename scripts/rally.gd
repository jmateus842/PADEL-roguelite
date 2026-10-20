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

## the return shot lives in shot_planner.gd, shared with the opponent
const Planner := preload("res://scripts/shot_planner.gd")

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
	var aim_x := 5.0 + clampf(aim, -1.0, 1.0) * Planner.AIM_SPREAD
	var shot := Planner.plan(contact, aim_x)
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
