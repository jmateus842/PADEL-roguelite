extends Node2D
## Ball lab: fires the sim's shots on the grey box court so you can compare
## them with sim/shots/*.png. No players, no score, no menus.
##
##                 keyboard     gamepad
## previous / next  Left/Right   D-pad left/right or LB/RB
## jump to a shot   1-9          (keyboard only)
## replay           Space        Start
## speed            T            D-pad up      1x, 0.25x, 0.1x
## auto replay      R            D-pad down
## check all        C            Back          compare every shot with sim/shots/summary.md
## Bindings live in scripts/controls.gd.

const BallModel := preload("res://scripts/ball_model.gd")
const Shots := preload("res://scripts/shots.gd")
const BallView := preload("res://scripts/ball.gd")

# side view panel: y along the court across, height up. same layout as the plots
const SV_ORIGIN := Vector2(440, 260)   # where y = 0, z = 0 sits on screen
const SV_PX_Y := 38.0
const SV_PX_Z := 40.0
const SPEEDS := [1.0, 0.25, 0.1]
const KEY_HINT := "Left/Right shot   1-9 jump   Space replay   T speed   R auto   C check all"
const PAD_HINT := "D-pad or LB/RB shot   Start replay   D-pad up speed   D-pad down auto   Back check all"

@onready var ball := $Court/Ball
@onready var info: Label = $Hud/Info

var shot_names: Array = Shots.names()
var current := 0
var speed_i := 0
var auto_replay := true
var expected := {}
var check_text := ""


func _ready() -> void:
	expected = Shots.expected_rows()
	ball.point_over.connect(_on_point_over)
	# optional start shot: godot --path . -- --shot=double_wall
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot=") and shot_names.has(arg.trim_prefix("--shot=")):
			current = shot_names.find(arg.trim_prefix("--shot="))
		elif arg == "--check":
			_run_check()
	_fire()


func _fire() -> void:
	var s: Array = Shots.SHOTS[shot_names[current]]
	ball.play(s[0], BallModel.launch(s[0], s[1], s[2], s[3]), s[4])
	ball.time_scale = SPEEDS[speed_i]


func _on_point_over(_result: String) -> void:
	if auto_replay:
		await get_tree().create_timer(1.2).timeout
		if ball.model.is_done():
			_fire()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lab_next"):
		current = (current + 1) % shot_names.size()
		_fire()
	elif event.is_action_pressed("lab_prev"):
		current = (current - 1 + shot_names.size()) % shot_names.size()
		_fire()
	elif event.is_action_pressed("lab_replay"):
		_fire()
	elif event.is_action_pressed("lab_speed"):
		speed_i = (speed_i + 1) % SPEEDS.size()
		ball.time_scale = SPEEDS[speed_i]
	elif event.is_action_pressed("lab_auto"):
		auto_replay = not auto_replay
		if auto_replay and ball.model.is_done():
			_fire()
	elif event.is_action_pressed("lab_check"):
		_run_check()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < shot_names.size():
			current = k - KEY_1
			_fire()


func _run_check() -> void:
	var results := Shots.run_all()
	var ok := 0
	var lines: PackedStringArray = []
	for shot_name in results:
		var m = results[shot_name].match
		if m == true:
			ok += 1
		else:
			lines.append("%s %s" % ["no sim row" if m == null else "DIFF", shot_name])
	check_text = "Check vs sim: %d/%d match" % [ok, results.size()]
	if not lines.is_empty():
		check_text += "\n" + "\n".join(lines)


func _process(_delta: float) -> void:
	queue_redraw()
	_update_info()


func _update_info() -> void:
	var m = ball.model
	var shot_name: String = shot_names[current]
	var t := "[%d/%d] %s   speed %sx   auto %s\n" % [current + 1, shot_names.size(), shot_name, SPEEDS[speed_i], "on" if auto_replay else "off"]
	t += "t %.2fs   height %.2f m\n\n" % [m.t, max(m.z, 0.0)]
	if m.is_done():
		t += "Result: %s\nHittable time: %.2fs in %d window(s)\n%s\n" % [m.end, m.hittable_time(), m.playable_windows().size(), m.describe()]
		if expected.has(shot_name):
			t += "\nSame as the sim: %s\n" % ("yes" if m.summary_row(shot_name) == expected[shot_name] else "NO")
	else:
		t += "%s\n" % m.describe()
	if check_text != "":
		t += "\n" + check_text + "\n"
	var pads := Controls.pad_names()
	t += "\nController: %s" % (", ".join(pads) if not pads.is_empty() else "none")
	if not pads.is_empty():
		var v := Controls.move_vector()
		t += "   left stick %+.2f %+.2f" % [v.x, v.y]
	t += "\n" + (PAD_HINT if Controls.using_gamepad else KEY_HINT)
	info.text = t


func _sv(y: float, z: float) -> Vector2:
	return SV_ORIGIN + Vector2(y * SV_PX_Y, -z * SV_PX_Z)


func _draw() -> void:
	# side view. x is flattened out, so side walls don't show here
	var L := BallModel.L
	draw_rect(Rect2(_sv(0, BallModel.REACH_HIGH), Vector2(L * SV_PX_Y, (BallModel.REACH_HIGH - BallModel.REACH_LOW) * SV_PX_Z)), Color(0.17, 0.63, 0.17, 0.12))
	draw_line(_sv(-0.5, 0), _sv(L + 0.5, 0), Color.WHITE, 1)
	draw_line(_sv(BallModel.NET_Y, 0), _sv(BallModel.NET_Y, BallModel.NET_H), Color.WHITE, 3)
	for wy in [0.0, L]:
		draw_line(_sv(wy, 0), _sv(wy, 3), Color("#3a8fd6"), 5)
		draw_line(_sv(wy, 3), _sv(wy, 4), Color("#888888"), 3)
	draw_string(ThemeDB.fallback_font, _sv(0, 4.6), "Side view (y along the court, height up). Green band = comfortable hitting height", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)

	var m = ball.model
	var p: PackedFloat64Array = m.path
	var n := p.size() / 4
	var pts := PackedVector2Array()
	for i in range(0, n, BallView.TRAIL_EVERY):
		pts.append(_sv(p[i * 4 + 2], p[i * 4 + 3]))
	if n > 0:
		pts.append(_sv(m.y, max(m.z, 0.0)))
	if pts.size() > 1:
		draw_polyline(pts, Color(0.85, 0.85, 0.85), 1.5)
	for e in m.events:
		if BallView.MARKERS.has(e.kind):
			draw_circle(_sv(e.y, e.z), 4.0, BallView.MARKERS[e.kind])
	if n > 0:
		draw_circle(_sv(m.y, max(m.z, 0.0)), 5.0, Color("#e8f55a"))
