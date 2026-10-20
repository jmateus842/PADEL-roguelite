extends Node2D
## Match court: you on the near half against a basic opponent on the far half.
## Plain padel, no powerups, a plain point count. Playtest 1 runs here.
##
##                     keyboard     gamepad
## move                WASD         left stick
## swing / serve       J            A (cross)
## aim your shot       hold A/D     stick left/right while you swing
## slow motion         T            D-pad up      1x, 0.5x, 0.25x
## Bindings live in scripts/controls.gd. Rules live in match_rules.gd,
## the opponent and its difficulty knobs in opponent.gd.
##
## Optional: godot --path . -- --demo   (an opponent plays your side too)

const BallModel := preload("res://scripts/ball_model.gd")
const Court := preload("res://scripts/court.gd")
const Rules := preload("res://scripts/match_rules.gd")
const Opponent := preload("res://scripts/opponent.gd")
const BallView := preload("res://scripts/ball.gd")

const SPEEDS := [1.0, 0.5, 0.25]
## pause after a point, game seconds
const PAUSE := 1.2
## height gauge next to the court: screen position of its floor, px per meter
const GAUGE_FLOOR := Vector2(400, 650)
const GAUGE_PPM := 60.0

const KEY_HINT := "WASD move   J swing / serve (hold A/D to aim)   T slow"
const PAD_HINT := "Stick move   A swing / serve (stick aims)   D-pad up slow"

@onready var court: Node2D = $Court
@onready var ball := $Court/Ball
@onready var player := $Court/Player
@onready var opponent_body := $Court/Opponent
@onready var info: Label = $Hud/Info

var rules
var opponent
## demo mode only: a second brain playing your side
var stand_in
var speed_i := 0
var wait := 0.0


func _ready() -> void:
	opponent_body.color = opponent_body.FAR_COLOR
	rules = Rules.new(ball, player, opponent_body)
	opponent = Opponent.new(rules, "far")
	if "--demo" in OS.get_cmdline_user_args():
		stand_in = Opponent.new(rules, "near", 7)


func _physics_process(delta: float) -> void:
	# runs before the ball (a child), so both players move first each tick
	var scale: float = SPEEDS[speed_i]
	var dt := delta * scale
	var stick := Controls.move_vector()
	if stand_in:
		stand_in.tick(dt)
	elif rules.state == "serve":
		player.tick(Vector2.ZERO, dt)   # hold your spot until the serve
	else:
		player.tick(stick, dt)
	opponent.tick(dt)
	rules.aim = stick.x
	rules.tick(dt)
	ball.time_scale = scale
	player.ball_in_reach = rules.in_reach("near")
	opponent_body.ball_in_reach = rules.in_reach("far")
	if rules.state == "over":
		wait += dt
		if wait >= PAUSE:
			wait = 0.0
			rules.next_point()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("swing") and not stand_in:
		if rules.state == "serve" and rules.server == "near":
			rules.serve()
		else:
			player.start_swing()
	elif event.is_action_pressed("lab_speed"):
		speed_i = (speed_i + 1) % SPEEDS.size()


func _process(_delta: float) -> void:
	queue_redraw()
	_update_info()


func _update_info() -> void:
	var r = rules
	var t := "MATCH: you (near) vs the opponent (far)%s\n" % ("   DEMO" if stand_in else "")
	t += "Score  you %d - %d opponent      speed %sx\n" % [r.score.near, r.score.far, SPEEDS[speed_i]]
	if r.state == "serve":
		t += "Your serve: press swing\n" if r.server == "near" and not stand_in else "Opponent serves\n"
	else:
		t += "Rally %d hits   longest %d\n" % [r.rally_len, r.longest_rally]
	t += "\nLast: %s\n" % (r.last if r.last != "" else "-")
	var h: Dictionary = r.your_hits
	t += "\nYour hits: volley %d   after the bounce %d   off the glass %d\n" % [h.volley, h.bounce, h.glass]
	if not r.your_heights.is_empty():
		var sum := 0.0
		for z in r.your_heights:
			sum += z
		t += "Average contact height %.2f m\n" % (sum / r.your_heights.size())
	t += "Opponent lobs %d   whiffs %d\n" % [r.opp_lobs, opponent.whiffs]
	var b: Vector3 = r.ball_court()
	t += "\nBall height %.2f m%s\n" % [maxf(b.z, 0.0), "   IN REACH" if player.ball_in_reach else ""]
	t += "Band %.1f to %.1f m   reach %.1f m\n" % [player.BAND_LOW, player.BAND_HIGH, player.REACH]
	t += "\n" + (PAD_HINT if Controls.using_gamepad else KEY_HINT)
	info.text = t


func _draw() -> void:
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
	var z: float = clampf(rules.ball_court().z, 0.0, 4.0)
	draw_circle(GAUGE_FLOOR - Vector2(0, z * GAUGE_PPM), 6.0, BallView.height_color(z))
	draw_string(ThemeDB.fallback_font, top - Vector2(14, 10), "height", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


func _exit_tree() -> void:
	# rules and brains point at each other, break the loop so both get freed
	rules.brains.clear()
