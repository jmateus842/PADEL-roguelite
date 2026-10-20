extends Node2D
## Practice court for playtest 1: a feeder on the far half sends the sim's
## shots, you return them from the near half. Plain padel, no powerups.
##
##                     keyboard     gamepad
## move                WASD         left stick
## swing               J            A (cross)
## aim the return      hold A/D     stick left/right while you swing
## next feed now       Space        R3 (click the right stick)
## pick one feed       Left/Right   D-pad left/right or LB/RB   (repeats it)
## mix all feeds       R            D-pad down
## slow motion         T            D-pad up      1x, 0.5x, 0.25x
## Bindings live in scripts/controls.gd. Tuning lives in player.gd and rally.gd.

const BallModel := preload("res://scripts/ball_model.gd")
const Court := preload("res://scripts/court.gd")
const Rally := preload("res://scripts/rally.gd")
const Shots := preload("res://scripts/shots.gd")
const BallView := preload("res://scripts/ball.gd")

const SPEEDS := [1.0, 0.5, 0.25]
## pause between points, game seconds
const PAUSE := 1.0
## height gauge next to the court: screen position of its floor, px per meter
const GAUGE_FLOOR := Vector2(400, 650)
const GAUGE_PPM := 60.0

const KEY_HINT := "WASD move   J swing (hold A/D to aim)   Space next feed   Left/Right pick feed   R mix   T slow"
const PAD_HINT := "Stick move   A swing (stick aims)   R3 next feed   D-pad/LB/RB pick feed   D-pad down mix   D-pad up slow"

@onready var court: Node2D = $Court
@onready var ball := $Court/Ball
@onready var player := $Court/Player
@onready var info: Label = $Hud/Info

var rally
var speed_i := 0
## true: shuffled mix of every feed. false: repeat FEEDS[pick]
var mix := true
var pick := 0
var wait := 0.5
var _order: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	rally = Rally.new(ball, player)
	# optional: godot --path . -- --feed=lob   (repeat one feed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--feed=") and Rally.FEEDS.has(arg.trim_prefix("--feed=")):
			mix = false
			pick = Rally.FEEDS.find(arg.trim_prefix("--feed="))


func next_feed() -> String:
	if not mix:
		return Rally.FEEDS[pick]
	if _order.is_empty():
		_order = Rally.FEEDS.duplicate()
		for i in range(_order.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = _order[i]
			_order[i] = _order[j]
			_order[j] = tmp
	return _order.pop_back()


func _feed_now() -> void:
	rally.feed(next_feed())
	wait = PAUSE


func _physics_process(delta: float) -> void:
	# runs before the ball (a child), so the player moves first each tick
	var scale: float = SPEEDS[speed_i]
	var stick := Controls.move_vector()
	player.tick(stick, delta * scale)
	rally.aim = stick.x
	ball.time_scale = scale
	player.ball_in_reach = rally.in_reach()
	if rally.state == "idle":
		wait -= delta * scale
		if wait <= 0.0:
			_feed_now()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("swing"):
		player.start_swing()
	elif event.is_action_pressed("lab_replay"):
		_feed_now()
	elif event.is_action_pressed("lab_next") or event.is_action_pressed("lab_prev"):
		# first press out of mix repeats the current feed, after that it steps
		if not mix:
			var step := 1 if event.is_action_pressed("lab_next") else -1
			pick = (pick + step + Rally.FEEDS.size()) % Rally.FEEDS.size()
		elif rally.feed_name != "":
			pick = Rally.FEEDS.find(rally.feed_name)
		mix = false
		_feed_now()
	elif event.is_action_pressed("lab_auto"):
		mix = not mix
		_order.clear()
	elif event.is_action_pressed("lab_speed"):
		speed_i = (speed_i + 1) % SPEEDS.size()


func _process(_delta: float) -> void:
	queue_redraw()
	_update_info()


func _update_info() -> void:
	var r = rally
	var t := "PRACTICE: return the feed\n"
	t += "Feed: %s   (%s)   speed %sx\n\n" % [r.feed_name if r.feed_name != "" else "-", "mix" if mix else "repeat", SPEEDS[speed_i]]
	t += "Fed %d   returned %d (in %d, errors %d)\n" % [r.fed, r.returned, r.returns_in, r.return_errors]
	t += "Missed %d   good leaves %d\n" % [r.missed, r.good_leaves]
	if r.fed > 0:
		t += "Return rate %d%%\n" % roundi(100.0 * r.returned / maxf(r.fed - r.good_leaves, 1.0))
	t += "\nLast: %s\n" % (r.last if r.last != "" else "-")
	var b: Vector3 = r.ball_court()
	t += "Ball height %.2f m%s\n" % [maxf(b.z, 0.0), "   IN REACH" if player.ball_in_reach else ""]
	t += "Band %.1f to %.1f m   reach %.1f m\n" % [player.BAND_LOW, player.BAND_HIGH, player.REACH]
	t += "\n" + (PAD_HINT if Controls.using_gamepad else KEY_HINT)
	info.text = t


func _draw() -> void:
	# feeder: where the feed came from, mirrored onto the far half
	if rally.feed_name != "":
		var s: Array = Shots.SHOTS[rally.feed_name]
		var at: Vector2 = court.position + Court.to_screen(BallModel.W - s[0][0], BallModel.L - s[0][1])
		draw_circle(at, 7.0, Color(0.6, 0.6, 0.6))
	# height gauge: floor to 4 m, green hitting band, ball marker
	var top := GAUGE_FLOOR - Vector2(0, 4.0 * GAUGE_PPM)
	draw_line(GAUGE_FLOOR, top, Color(1, 1, 1, 0.5), 2)
	var band_lo := GAUGE_FLOOR - Vector2(0, player.BAND_LOW * GAUGE_PPM)
	var band_hi := GAUGE_FLOOR - Vector2(0, player.BAND_HIGH * GAUGE_PPM)
	draw_rect(Rect2(band_hi - Vector2(8, 0), Vector2(16, band_lo.y - band_hi.y)), Color(0.17, 0.63, 0.17, 0.45))
	var net := GAUGE_FLOOR - Vector2(0, BallModel.NET_H * GAUGE_PPM)
	draw_line(net - Vector2(12, 0), net + Vector2(12, 0), Color.BLACK, 2)
	for m in [1, 2, 3, 4]:
		var y := GAUGE_FLOOR - Vector2(0, m * GAUGE_PPM)
		draw_line(y - Vector2(4, 0), y + Vector2(4, 0), Color(1, 1, 1, 0.5), 1)
		draw_string(ThemeDB.fallback_font, y + Vector2(10, 5), "%d m" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var z: float = clampf(rally.ball_court().z, 0.0, 4.0)
	draw_circle(GAUGE_FLOOR - Vector2(0, z * GAUGE_PPM), 6.0, BallView.height_color(z))
	draw_string(ThemeDB.fallback_font, top - Vector2(14, 10), "height", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
