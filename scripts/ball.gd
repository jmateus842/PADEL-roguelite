extends Node2D
## Draws the ball model on the court: shadow at the true (x, y), ball lifted by z.
## Steps the model at its own fixed DT inside _physics_process, so it plays back
## the same path as the sim at any frame rate (about 8 substeps per 60 Hz tick).
##
## The model always plays from the near half toward the far half. A ball the
## opponent hits plays with flipped = true: same model, drawn turned around
## (x to W - x, y to L - y). The court is symmetric, so every rule still holds.

const BallModel := preload("res://scripts/ball_model.gd")
const Court := preload("res://scripts/court.gd")

## how far up the screen 1 m of height lifts the ball, in court meters
const HEIGHT_DRAW := 0.6
const RADIUS := 5.0
const TRAIL_EVERY := 5   # draw every Nth path point

const MARKERS := {
	"floor": Color("#d62728"),
	"glass": Color("#1f77b4"),
	"mesh": Color("#555555"),
	"net": Color.BLACK,
	"over the wall": Color("#ff7f0e"),
}

signal point_over(result: String)

var model = BallModel.new()
var time_scale := 1.0
## true: the model's near half is the far half on screen (opponent's shot)
var flipped := false
## optional. called after every model step, returns true when it replaced
## the ball (a hit), which ends the substeps for this tick
var hit_check: Callable
var _acc := 0.0
var _announced := true


## until the first play() the ball sits idle: no stepping, nothing drawn
func _init() -> void:
	model.end = "idle"


func play(start: Array, vel: Array, kick := 1.0, from_far := false) -> void:
	flipped = from_far
	model.reset(start, vel, kick)
	_acc = 0.0
	_announced = false
	queue_redraw()


func _physics_process(delta: float) -> void:
	if model.is_done():
		if not _announced:
			_announced = true
			point_over.emit(model.end)
		return
	_acc += delta * time_scale
	while _acc >= BallModel.DT and not model.is_done():
		model.step()
		_acc -= BallModel.DT
		if hit_check.is_valid() and hit_check.call():
			break
	queue_redraw()


## model x, y to court x, y as seen on screen
func world(x: float, y: float) -> Vector2:
	return Vector2(BallModel.W - x, BallModel.L - y) if flipped else Vector2(x, y)


func _screen(x: float, y: float) -> Vector2:
	var w := world(x, y)
	return Court.to_screen(w.x, w.y)


static func height_color(h: float) -> Color:
	# dark purple on the floor to yellow at 4 m, close to the plots' plasma map
	return Color("#0d0887").lerp(Color("#f0f921"), clampf(h / 4.0, 0.0, 1.0))


func _draw() -> void:
	var p: PackedFloat64Array = model.path
	var n := p.size() / 4
	if n == 0:
		return
	# shadow trail on the court, colored by height
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in range(0, n, TRAIL_EVERY):
		pts.append(_screen(p[i * 4 + 1], p[i * 4 + 2]))
		cols.append(height_color(p[i * 4 + 3]))
	if pts.size() > 1:
		draw_polyline_colors(pts, cols, 2.0)
	# events: where the ball touched something
	for e in model.events:
		if MARKERS.has(e.kind):
			draw_circle(_screen(e.x, e.y), 4.0, MARKERS[e.kind])
	# the ball itself
	var x: float = model.x
	var y: float = model.y
	var z: float = max(model.z, 0.0)
	var ground := _screen(x, y)
	var shadow_r := RADIUS * (1.0 - clampf(z / 8.0, 0.0, 0.5))
	draw_set_transform(ground, 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, shadow_r, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO)
	var lifted := ground - Vector2(0, z * HEIGHT_DRAW * Court.PPM)
	draw_line(ground, lifted, Color(1, 1, 1, 0.15), 1.0)
	draw_circle(lifted, RADIUS * (1.0 + z * 0.06), Color("#e8f55a"))
