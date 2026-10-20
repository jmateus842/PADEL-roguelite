extends Node2D
## The player on the near half, top down. Position in court meters, like the ball.
## Moves with Controls.move_vector() and swings with the "swing" action.
## practice.gd feeds it input each tick, so tests can drive it directly.
##
## Hitting: while a swing is active, the ball counts as in reach when its true
## position (the shadow) is within REACH of the player and its height sits in
## the band. The band is the design question for playtest 1, so it lives here
## as its own constants, separate from the sim's REACH_LOW/HIGH.

const BallModel := preload("res://scripts/ball_model.gd")
const Court := preload("res://scripts/court.gd")

# --- tuning ---
## top speed and how fast you get there, m/s and m/s²
const SPEED := 5.5
const ACCEL := 45.0
## racket reach from the body center, m
const REACH := 1.1
## hitting band, m. starts as the sim's comfortable height
const BAND_LOW := 0.3
const BAND_HIGH := 1.9
## a swing is live this long, then you wait COOLDOWN before the next one, s
const SWING_ACTIVE := 0.18
const COOLDOWN := 0.25
## how close you can get to the walls and the net, m
const WALL_GAP := 0.3
const NET_GAP := 0.4

const BODY := 0.3   # drawn radius, m
const COLOR := Color("#f2f2f2")

var px := 5.0
var py := 2.5
var vel := Vector2.ZERO
## > 0 while the swing is live, then counts down through the cooldown
var swing_left := 0.0
var cooldown_left := 0.0
## set by practice.gd each tick, only for drawing
var ball_in_reach := false
var flash := 0.0   # short highlight after a hit


func reset(at := Vector2(5.0, 2.5)) -> void:
	px = at.x
	py = at.y
	vel = Vector2.ZERO
	swing_left = 0.0
	cooldown_left = 0.0


## stick or WASD as given by Controls.move_vector(): screen up is toward the net
func tick(stick: Vector2, delta: float) -> void:
	var want := Vector2(stick.x, -stick.y).limit_length(1.0) * SPEED
	vel = vel.move_toward(want, ACCEL * delta)
	px += vel.x * delta
	py += vel.y * delta
	var lo := Vector2(WALL_GAP, WALL_GAP)
	var hi := Vector2(BallModel.W - WALL_GAP, BallModel.NET_Y - NET_GAP)
	if px < lo.x or px > hi.x:
		vel.x = 0.0
	if py < lo.y or py > hi.y:
		vel.y = 0.0
	px = clampf(px, lo.x, hi.x)
	py = clampf(py, lo.y, hi.y)
	if swing_left > 0.0:
		swing_left -= delta
		if swing_left <= 0.0:
			cooldown_left = COOLDOWN
	elif cooldown_left > 0.0:
		cooldown_left -= delta
	flash = maxf(flash - delta, 0.0)
	queue_redraw()


func start_swing() -> bool:
	if swing_left > 0.0 or cooldown_left > 0.0:
		return false
	swing_left = SWING_ACTIVE
	return true


func is_swinging() -> bool:
	return swing_left > 0.0


## the swing connected: one hit per swing, cooldown starts now
func used_swing() -> void:
	swing_left = 0.0
	cooldown_left = COOLDOWN
	flash = 0.15


## ball at court position (bx, by) and height bz: close enough and in the band?
func can_reach(bx: float, by: float, bz: float) -> bool:
	var dx := bx - px
	var dy := by - py
	return dx * dx + dy * dy <= REACH * REACH and BAND_LOW <= bz and bz <= BAND_HIGH


func _draw() -> void:
	var c := Court.to_screen(px, py)
	var reach_px := REACH * Court.PPM
	# reach ring: green when the ball is playable right now
	var ring := Color(0.3, 1.0, 0.4, 0.9) if ball_in_reach else Color(1, 1, 1, 0.35)
	if is_swinging():
		draw_circle(c, reach_px, Color(1, 1, 1, 0.12))
	if flash > 0.0:
		draw_circle(c, reach_px, Color(1.0, 0.9, 0.3, 0.35))
	draw_arc(c, reach_px, 0.0, TAU, 40, ring, 1.5)
	draw_circle(c, BODY * Court.PPM, COLOR)
	draw_circle(c, BODY * Court.PPM * 0.45, Color("#c0392b"))
