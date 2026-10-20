extends RefCounted
## Match rules: you on the near half, the opponent on the far half, real points.
## Plain object on top of the ball and the two bodies, so tests can run it
## without a scene. Each side is "near" or "far". A side with a brain
## (opponent.gd) plays itself. A side without one waits for "swing".
##
## A point: the server serves diagonally into the service box, then the ball
## goes back and forth until the ball model ends it. The model always judges
## from the hitter's side, so a result starting with "winner" goes to the
## hitter and anything else (net, out, fault) goes to the other side.
##
## Simplified for playtest 1: the server changes every point, serves are
## auto-aimed into the box, and the score is a plain point count.

const BallModel := preload("res://scripts/ball_model.gd")
const Planner := preload("res://scripts/shot_planner.gd")

## where the server stands, model coordinates (always the near half there)
const SERVE_X := 7.0
const SERVE_Y := 1.5
const SERVE_Z := 0.8
## the serve lands this deep, inside the service box (box ends at 16.95)
const SERVE_DEPTH := 15.0
const SERVE_SPEED := 14.0
## the receiver waits this deep, model coordinates
const RECEIVE_Y := 18.0
## the opponent serves this long after the point starts, s
const AUTO_SERVE := 0.8

var ball    # ball.gd
var bodies := {}   # side -> player.gd
var brains := {}   # side -> opponent.gd, sides without one are yours
## "serve": waiting for the server. "play": ball live. "over": point done
var state := "serve"
var server := "near"
var last_hitter := ""
## counts every launch, so a brain knows when a new ball is coming
var shot_id := 0
## stick x when you hit, -1 to 1. The scene sets it every tick
var aim := 0.0
var serve_wait := AUTO_SERVE

var score := {"near": 0, "far": 0}
var points := 0
## hits in the current point, serve included
var rally_len := 0
var longest_rally := 0
## what happened last point, for the HUD
var last := ""
## your hits by how the ball reached you, and the contact heights
var your_hits := {"volley": 0, "bounce": 0, "glass": 0}
var your_heights: Array[float] = []
var opp_lobs := 0


func _init(ball_node, near_body, far_body) -> void:
	ball = ball_node
	bodies = {"near": near_body, "far": far_body}
	near_body.far = false
	far_body.far = true
	ball.hit_check = try_hit
	ball.point_over.connect(on_point_over)
	setup_serve()


static func other(side: String) -> String:
	return "far" if side == "near" else "near"


## court position to the model coordinates of a hitter on `side`
static func to_model(side: String, p: Vector3) -> Array:
	if side == "far":
		return [BallModel.W - p.x, BallModel.L - p.y, p.z]
	return [p.x, p.y, p.z]


static func to_court(side: String, x: float, y: float) -> Vector2:
	return Vector2(BallModel.W - x, BallModel.L - y) if side == "far" else Vector2(x, y)


## the ball's true court position (the shadow) and height
func ball_court() -> Vector3:
	var w: Vector2 = ball.world(ball.model.x, ball.model.y)
	return Vector3(w.x, w.y, ball.model.z)


## who may hit the ball next, "" between points
func receiver() -> String:
	return other(last_hitter) if state == "play" else ""


## padel rules for the receiver: the ball is alive and has crossed to their side.
## Volleys count, no bounce needed
func playable_for(side: String) -> bool:
	return state == "play" and receiver() == side and not ball.model.is_done() and ball.model.crossed()


func in_reach(side: String) -> bool:
	if not playable_for(side):
		return false
	var b := ball_court()
	return bodies[side].can_reach(b.x, b.y, b.z)


## server on the right on even points, on the left on odd ones, receiver
## diagonally across at the back
func serve_x() -> float:
	return SERVE_X if points % 2 == 0 else BallModel.W - SERVE_X


func setup_serve() -> void:
	state = "serve"
	last_hitter = ""
	rally_len = 0
	serve_wait = AUTO_SERVE
	var sx := serve_x()
	bodies[server].reset(to_court(server, sx, SERVE_Y))
	bodies[other(server)].reset(to_court(server, BallModel.W - sx, RECEIVE_Y))


## counts down the opponent's serve. The scene calls it every tick
func tick(delta: float) -> void:
	if state == "serve" and brains.has(server):
		serve_wait -= delta
		if serve_wait <= 0.0:
			serve()


## you serve with "swing". Returns false when it isn't your serve
func serve() -> bool:
	if state != "serve":
		return false
	var sx := serve_x()
	var contact := [sx, SERVE_Y, SERVE_Z]
	var target_x := BallModel.W - sx + signf(5.0 - sx) * 0.5
	_launch(server, contact, Planner.plan(contact, target_x, SERVE_DEPTH, SERVE_SPEED))
	return true


func _launch(side: String, contact_model: Array, vel: Array) -> void:
	ball.play(contact_model, vel, 1.0, side == "far")
	last_hitter = side
	state = "play"
	shot_id += 1
	rally_len += 1


## ball.gd calls this after every model step
func try_hit() -> bool:
	var side := receiver()
	if side == "" or not bodies[side].is_swinging() or not in_reach(side):
		return false
	var b := ball_court()
	var contact := to_model(side, b)
	var vel: Array
	if brains.has(side):
		vel = brains[side].choose_shot(contact)
		if brains[side].last_was_lob and side == "far":
			opp_lobs += 1
	else:
		vel = Planner.plan(contact, 5.0 + clampf(aim, -1.0, 1.0) * Planner.AIM_SPREAD)
	if side == "near":
		your_hits[_how_it_came()] += 1
		your_heights.append(b.z)
	bodies[side].used_swing()
	_launch(side, contact, vel)
	return true


## the incoming ball, in its own model coordinates the receiver is the far half
func _how_it_came() -> String:
	var bounced := false
	for e in ball.model.events:
		if (e.kind == "glass" or e.kind == "mesh") and e.y > BallModel.NET_Y:
			return "glass"
		if e.kind == "floor" and e.detail == "far":
			bounced = true
	return "bounce" if bounced else "volley"


func on_point_over(result: String) -> void:
	if state != "play":
		return
	var hitter := last_hitter
	var hitter_wins := result.begins_with("winner") or result == "ball died" or result == "timeout"
	var winner := hitter if hitter_wins else other(hitter)
	score[winner] += 1
	points += 1
	longest_rally = maxi(longest_rally, rally_len)
	var who := "You" if winner == "near" else "Opponent"
	var by := "your" if hitter == "near" else "their"
	last = "%s won the point (%s shot: %s, %d hits)" % [who, by, result, rally_len]
	state = "over"


## the scene calls this after the pause between points
func next_point() -> void:
	server = other(server)
	setup_serve()
