extends Node2D
## Match court: you on the near half against a basic opponent on the far half.
## Plain padel, no powerups, a plain point count. Playtest 1 runs here.
##
##                     keyboard     gamepad
## move                WASD         left stick
## swing / serve       J            A (cross)
## aim your shot       hold A/D     stick left/right while you swing
## slow motion         T            D-pad up      1x, 0.5x, 0.25x
## menu                Esc          Start         pick vs the opponent or watch
## stats panel         Tab          from the menu
## Bindings live in scripts/controls.gd. Rules live in match_rules.gd,
## the opponent and its difficulty knobs in opponent.gd.
##
## Optional: godot --path . -- --demo   starts in opponent vs opponent

const BallModel := preload("res://scripts/ball_model.gd")
const Court := preload("res://scripts/court.gd")
const Rules := preload("res://scripts/match_rules.gd")
const Opponent := preload("res://scripts/opponent.gd")
const BallView := preload("res://scripts/ball.gd")
const Menu := preload("res://scripts/match_menu.gd")

const SPEEDS := [1.0, 0.5, 0.25]
## pause after a point, game seconds
const PAUSE := 1.2
## height gauge right of the court: screen position of its floor, px per meter
const GAUGE_FLOOR := Vector2(835, 640)
const GAUGE_PPM := 60.0

const KEY_HINT := "WASD move    J swing    T slow    Tab stats + overlay    Esc menu"
const PAD_HINT := "Stick move    A swing    D-pad up slow    Start menu"

# --- HUD look ---
const CARD_BG := Color(0.08, 0.09, 0.11, 0.88)
const DIM := Color(1, 1, 1, 0.55)
const YOU_COLOR := Color("#f2f2f2")
const OPP_COLOR := Color("#f39c12")
## how stretched the opponent is: rules.strain_name() to a color
const STRAIN_COLORS := {
	"easy": Color("#2ecc71"),
	"working": Color("#f1c40f"),
	"stretched": Color("#e74c3c"),
}
## pop-up labels and landing marks live this long, real seconds
const POP_LIFE := 1.2
const LOG_HEADER := "row,point,shot,side,came,kind,net,lob,contact_x,contact_y,height,land_x,land_y,pressure,strain,winner,result,by,cause"

## readable endings for the ball model's results
const ENDINGS := {
	"winner: second bounce": "two bounces",
	"winner: came back over the net": "came back over the net",
	"winner: out over the back wall": "out over the back wall",
	"winner: out over the side wall": "out over the side wall",
	"net": "into the net",
	"out": "out",
	"fault: bounced on our side": "bounced on own side",
	"fault: hit our own mesh": "hit own mesh",
	"ball died": "ball died",
	"timeout": "ball rolled out the clock",
}

## true: an opponent plays your side too. Static so it survives the restart
## when you pick a mode in the menu
static var demo_mode := "--demo" in OS.get_cmdline_user_args()
## stats panel on the right. Static so it stays as you left it after a restart
static var stats_on := false

@onready var court: Node2D = $Court
@onready var ball := $Court/Ball
@onready var player := $Court/Player
@onready var opponent_body := $Court/Opponent
@onready var hud: CanvasLayer = $Hud

var rules
var opponent
## demo mode only: a second brain playing your side
var stand_in
var speed_i := 0
var wait := 0.0

var _score_you: Label
var _score_opp: Label
var _mode: Label
var _status: Label
var _last: Label
var _stats_card: PanelContainer
var _stats: Label
var _hint: Label
var _menu
## overlay: floating labels and landing marks, each {text, at (court m), color, age}
var _pops: Array[Dictionary] = []
var _seen_shot := 0
var _seen_points := 0
var _log: FileAccess


func _ready() -> void:
	opponent_body.color = opponent_body.FAR_COLOR
	rules = Rules.new(ball, player, opponent_body)
	opponent = Opponent.new(rules, "far")
	if demo_mode:
		stand_in = Opponent.new(rules, "near", 7)
	_build_hud()
	_menu = Menu.new()
	_menu.mode_picked.connect(_on_mode_picked)
	_menu.stats_toggled.connect(_set_stats)
	add_child(_menu)
	_menu.set_stats_label(stats_on)
	_open_log()


## restart the match in the picked mode, fresh score
func _on_mode_picked(demo: bool) -> void:
	demo_mode = demo
	get_tree().reload_current_scene()


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
	elif event.is_action_pressed("stats"):
		_set_stats(not stats_on)


func _set_stats(on: bool) -> void:
	stats_on = on
	_stats_card.visible = on
	_menu.set_stats_label(on)


func _process(delta: float) -> void:
	_watch_rules()
	for p in _pops:
		p.age += delta
	_pops = _pops.filter(func(p): return p.age < POP_LIFE)
	queue_redraw()
	_update_info()


## turn new hits and point endings into pop-ups and log rows
func _watch_rules() -> void:
	var r = rules
	for h in r.hits:
		if h.shot <= _seen_shot:
			continue
		_seen_shot = h.shot
		if h.side == "near" and h.kind != "serve":
			var text: String = h.kind.to_upper() + ("  NET" if h.net else "")
			_pops.append({"text": text, "at": Vector2(h.x, h.y), "color": YOU_COLOR, "age": 0.0})
			_pops.append({"text": "x", "at": Vector2(h.land_x, h.land_y), "color": YOU_COLOR, "age": 0.0, "mark": true})
		elif h.side == "far" and h.lob:
			_pops.append({"text": "LOB", "at": Vector2(h.x, h.y), "color": OPP_COLOR, "age": 0.0})
	if r.points != _seen_points:
		_seen_points = r.points
		if r.last_whiff != "":
			var at: Vector2 = opponent_body.pos()
			_pops.append({"text": "WHIFF", "at": at, "color": STRAIN_COLORS[r.last_whiff], "age": 0.0})
		_write_point()


func _open_log() -> void:
	var dir := "res://logs" if OS.has_feature("editor") else "user://logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	# keep Godot from importing the logs: it reads any .csv as a translation
	if not FileAccess.file_exists(dir + "/.gdignore"):
		FileAccess.open(dir + "/.gdignore", FileAccess.WRITE)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/match_%s%s.csv" % [dir, stamp, "_watch" if stand_in else ""]
	_log = FileAccess.open(path, FileAccess.WRITE)
	if _log:
		_log.store_line(LOG_HEADER)


func _write_point() -> void:
	if not _log:
		return
	var r = rules
	var n: int = r.points
	for h in r.hits:
		_log.store_line("hit,%d,%d,%s,%s,%s,%s,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,,,," % [
			n, h.shot, h.side, h.came, h.kind, h.net, h.lob,
			h.x, h.y, h.z, h.land_x, h.land_y, h.pressure, h.strain])
	_log.store_line("point,%d,,,,,,,,,,,,,,%s,\"%s\",%s,\"%s\"" % [n, r.last_winner, r.last_result, r.last_by, r.last_cause])
	_log.flush()


func _card(pos: Vector2, width: float) -> VBoxContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", style)
	card.position = pos
	card.custom_minimum_size = Vector2(width, 0)
	hud.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	return box


func _label(box: Node, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


func _build_hud() -> void:
	# scoreboard, top left: always on
	var board := _card(Vector2(40, 60), 360)
	_mode = _label(board, 14, DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	board.add_child(row)
	_score_you = _label(row, 44, YOU_COLOR)
	_score_opp = _label(row, 44, OPP_COLOR)
	_score_you.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_opp.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status = _label(board, 18)
	_last = _label(board, 15, DIM)
	_last.custom_minimum_size = Vector2(324, 0)
	_status.custom_minimum_size = Vector2(324, 0)
	# stats, right: toggled
	var stats_box := _card(Vector2(900, 60), 340)
	_stats_card = stats_box.get_parent()
	_label(stats_box, 14, DIM).text = "STATS"
	_stats = _label(stats_box, 15)
	_stats.custom_minimum_size = Vector2(304, 0)
	_stats_card.visible = stats_on
	# controls, bottom left
	_hint = _label(hud, 13, DIM)
	_hint.position = Vector2(40, 680)
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF


func _update_info() -> void:
	var r = rules
	_mode.text = "WATCHING  opponent vs opponent" if stand_in else "MATCH  you vs the opponent"
	var you_name := "NEAR" if stand_in else "YOU"
	_score_you.text = "%s %d" % [you_name, r.score.near]
	_score_opp.text = "OPP %d" % r.score.far
	if r.state == "serve":
		if r.server == "near" and not stand_in:
			_status.text = "Your serve. Press %s" % ("A" if Controls.using_gamepad else "J")
		else:
			_status.text = "%s serve" % ("Near" if r.server == "near" else "Opponent's")
	elif r.state == "play":
		_status.text = "Rally  %d" % r.rally_len
	else:
		if r.last_winner == "near":
			_status.text = "Point to near" if stand_in else "Point to you"
		else:
			_status.text = "Point to the opponent"
	if r.last_result != "":
		var whose := ("near's" if stand_in else "your") if r.last_by == "near" else "their"
		var why: String = ENDINGS.get(r.last_result, r.last_result)
		if r.last_result.begins_with("out: hit their"):
			why = "hit the " + r.last_result.trim_prefix("out: hit their ")
		_last.text = "Last point: %s shot, %s" % [whose, why]
		if r.last_cause != "":
			_last.text += "\n" + r.last_cause[0].to_upper() + r.last_cause.substr(1)
	else:
		_last.text = "First point"
	_hint.text = PAD_HINT if Controls.using_gamepad else KEY_HINT
	if not stats_on:
		return
	var h: Dictionary = r.your_hits
	var t := "Rally %d hits   longest %d\n" % [r.rally_len, r.longest_rally]
	t += "Speed %sx\n\n" % SPEEDS[speed_i]
	t += "Your hits\n  volley %d\n  after the bounce %d\n  off the glass %d\n" % [h.volley, h.bounce, h.glass]
	if not r.your_heights.is_empty():
		var sum := 0.0
		for z in r.your_heights:
			sum += z
		t += "  average contact %.2f m\n" % (sum / r.your_heights.size())
	var k: Dictionary = r.tally
	t += "\nYour shots   hit / won the point\n"
	t += "  cross %d / %d   line %d / %d   mid %d / %d\n" % [k.cross.hit, k.cross.won, k.line.hit, k.line.won, k.mid.hit, k.mid.won]
	t += "  from the net %d / %d\n" % [k.net.hit, k.net.won]
	var w: Dictionary = r.whiff_tally
	t += "\nOpponent whiffs\n  easy %d   working %d   stretched %d\n" % [w.easy, w.working, w.stretched]
	t += "Opponent lobs %d   won the point %d\n" % [r.opp_lobs, r.lobbed_at_net]
	var b: Vector3 = r.ball_court()
	t += "\nBall height %.2f m%s\n" % [maxf(b.z, 0.0), "   IN REACH" if player.ball_in_reach else ""]
	t += "Band %.1f to %.1f m   reach %.1f m" % [player.BAND_LOW, player.BAND_HIGH, player.REACH]
	_stats.text = t


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
	if stats_on:
		_draw_overlay()


## court meters to this node's pixels
func _px(at: Vector2) -> Vector2:
	return court.position + Court.to_screen(at.x, at.y)


func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	# net zone on your half: inside it, the opponent lobs you
	var zy: float = BallModel.NET_Y - rules.NET_ZONE
	var inside: bool = player.py >= zy
	var a := _px(Vector2(0.0, BallModel.NET_Y))
	var b := _px(Vector2(BallModel.W, zy))
	draw_rect(Rect2(Vector2(a.x, a.y), Vector2(b.x - a.x, b.y - a.y)), Color(1.0, 0.6, 0.1, 0.16 if inside else 0.05))
	var x := 0.0
	while x < BallModel.W:
		draw_line(_px(Vector2(x, zy)), _px(Vector2(minf(x + 0.4, BallModel.W), zy)), Color(1, 1, 1, 0.45), 1.5)
		x += 0.8
	draw_string(font, _px(Vector2(0.15, zy)) + Vector2(0, 14), "net zone: they lob", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
	# ring under the opponent while it chases a ball it has read
	if rules.state == "play" and rules.receiver() == "far" and opponent.plan_id == rules.shot_id:
		var color: Color = STRAIN_COLORS[rules.strain_name(opponent.strain)]
		draw_arc(_px(opponent_body.pos()), 0.55 * Court.PPM, 0.0, TAU, 32, color, 3.0)
	# pop-ups fade and drift up, landing marks just fade
	for p in _pops:
		var fade: float = 1.0 - p.age / POP_LIFE
		var c: Color = p.color
		c.a = fade
		var at := _px(p.at)
		if p.get("mark", false):
			var s := 6.0
			draw_line(at - Vector2(s, s), at + Vector2(s, s), c, 2.0)
			draw_line(at - Vector2(s, -s), at + Vector2(s, -s), c, 2.0)
		else:
			draw_string(font, at + Vector2(-24, -22 - 20.0 * p.age), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c)


func _exit_tree() -> void:
	# rules and brains point at each other, break the loop so both get freed
	rules.brains.clear()
