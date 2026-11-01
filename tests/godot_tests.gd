extends SceneTree
## Godot half of the tests. Run from the repo root:
##   godot --headless --path . --script res://tests/godot_tests.gd
## Run tests/test_sim.py first, it writes the golden file this reads.
##
## 1. named shots: the 11 shots match sim/shots/summary.md
## 2. random shots: hundreds of random launches match the Python sim step for step
## 3. rules that must always hold: ball stays in the court, never under the floor,
##    never gains energy, same input gives the same path
## 4. playback: ball.gd plays at real speed and ends on the same path at any frame rate
## 5. controls: every action has its keyboard and gamepad bindings, no key or button does two jobs, WASD moves
## 6. player: stays on the near half, top speed, swing timing, reach and band
## 7. rally: feeds play mirrored, the receiver only plays a ball on our side,
##    every return from the near half lands in, every feed can be returned
##    through real playback, and the tally counts each kind of point
## 8. match: the far body stays on its half, lobs clear a player at the net and
##    land in, the opponent lobs only when you're close to the net and drives
##    away from you, points go to the right side, serves land in the box, and
##    opponent vs opponent plays long matches that always finish. The playtest
##    overlay data: shot kinds, net zone, landing spots, tallies and whiff causes
## Exit code 1 if anything fails.

const BallModel := preload("res://scripts/ball_model.gd")
const BallNode := preload("res://scripts/ball.gd")
const Shots := preload("res://scripts/shots.gd")
const Controls := preload("res://scripts/controls.gd")
const PlayerNode := preload("res://scripts/player.gd")
const Rally := preload("res://scripts/rally.gd")
const Planner := preload("res://scripts/shot_planner.gd")
const Rules := preload("res://scripts/match_rules.gd")
const Opponent := preload("res://scripts/opponent.gd")
const Focus := preload("res://scripts/focus.gd")
const Aim := preload("res://scripts/aim.gd")
const GOLDEN := "res://tests/golden_random.json"

## energy may creep up a little from the step size alone, never more than this (J/kg)
const ENERGY_SLACK := 0.05
## final position: Python and Godot should agree to this many meters
const FINAL_TOLERANCE := 1e-9

var failed := 0
var passed := 0


func _init() -> void:
	var cases := _load_cases()
	_suite_named_shots()
	_suite_random_shots(cases)
	_suite_invariants(cases)
	_suite_playback()
	_suite_controls()
	_suite_player()
	_suite_rally()
	_suite_match()
	_suite_focus()
	print("\nGodot: %s" % ("all good (%d checks)" % passed if failed == 0 else "%d failed, %d passed" % [failed, passed]))
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL  ", message)


func _summary(title: String, fails_before: int, detail := "") -> void:
	var tag := "  ok  " if failed == fails_before else "FAIL  "
	print(tag, title, ("  " + detail) if detail != "" else "")


func _load_cases() -> Array:
	var f := FileAccess.open(GOLDEN, FileAccess.READ)
	if f == null:
		_check(false, "can't open %s. Run python tests/test_sim.py first" % GOLDEN)
		return []
	var data = JSON.parse_string(f.get_as_text())
	return data.cases if data is Dictionary else []


func _run_case(c: Dictionary):
	var m = BallModel.new()
	m.reset(c.start, BallModel.launch(c.start, c.speed, c.elev, c.target), c.kick)
	m.run_to_end()
	return m


# --- 1 ---------------------------------------------------------------------

func _suite_named_shots() -> void:
	var before := failed
	var results := Shots.run_all()
	for shot_name in results:
		_check(results[shot_name].match == true, "named shot %s differs from summary.md\n      godot: %s" % [shot_name, results[shot_name].row])
	_summary("named shots match summary.md", before, "(%d)" % results.size())


# --- 2 ---------------------------------------------------------------------

func _suite_random_shots(cases: Array) -> void:
	var before := failed
	var worst := 0.0
	for c in cases:
		var m = _run_case(c)
		var row: String = m.summary_row(c.name)
		_check(row == c.row, "%s row differs\n      python: %s\n      godot:  %s" % [c.name, c.row, row])
		_check(m.path.size() / 4 == int(c.steps), "%s step count %d, python %d" % [c.name, m.path.size() / 4, int(c.steps)])
		_check(m.events.size() == int(c.events), "%s event count %d, python %d" % [c.name, m.events.size(), int(c.events)])
		var last: int = m.path.size() - 4
		for i in 4:
			worst = max(worst, abs(m.path[last + i] - float(c.final[i])))
		_check(worst <= FINAL_TOLERANCE, "%s final position off by %s m" % [c.name, worst])
	_summary("random shots match the Python sim", before, "(%d shots, worst final gap %s m)" % [cases.size(), worst])


# --- 3 ---------------------------------------------------------------------

func _suite_invariants(cases: Array) -> void:
	var before := failed
	var all_cases := cases.duplicate()
	for shot_name in Shots.SHOTS:
		var s: Array = Shots.SHOTS[shot_name]
		all_cases.append({"name": shot_name, "start": s[0], "speed": s[1], "elev": s[2], "target": s[3], "kick": s[4]})
	var max_gain := 0.0
	for c in all_cases:
		var m = BallModel.new()
		m.reset(c.start, BallModel.launch(c.start, c.speed, c.elev, c.target), c.kick)
		var e0 := _energy(m)
		var steps := 0
		while not m.is_done():
			m.step()
			steps += 1
			if float(c.kick) == 1.0:
				max_gain = max(max_gain, _energy(m) - e0)
		# t adds DT 2500 times and lands a hair under 5.0, so one extra step is normal (Python does it too)
		_check(m.t <= BallModel.MAX_T + BallModel.DT * 1.5, "%s ran past MAX_T" % c.name)
		var p: PackedFloat64Array = m.path
		var n := p.size() / 4
		for i in n:
			var t := p[i * 4]
			var x := p[i * 4 + 1]
			var y := p[i * 4 + 2]
			var z := p[i * 4 + 3]
			if z < -1e-12:
				_check(false, "%s under the floor at t %.3f (z %.4f)" % [c.name, t, z])
				break
			# the last point can sit past a wall when the ball left the court there
			var inside := x >= 0.0 and x <= BallModel.W and y >= 0.0 and y <= BallModel.L
			if not inside and i < n - 1:
				_check(false, "%s outside the court at t %.3f (%.2f, %.2f)" % [c.name, t, x, y])
				break
			if i > 0 and abs(t - p[(i - 1) * 4] - BallModel.DT) > 1e-9:
				_check(false, "%s time step isn't DT at t %.3f" % [c.name, t])
				break
		var last_t := -1.0
		for e in m.events:
			if e.t < last_t:
				_check(false, "%s events out of order" % c.name)
				break
			last_t = e.t
		# same input, same path
		var again = BallModel.new()
		again.reset(c.start, BallModel.launch(c.start, c.speed, c.elev, c.target), c.kick)
		again.run_to_end()
		_check(again.path == m.path and again.end == m.end, "%s isn't deterministic" % c.name)
	_check(max_gain <= ENERGY_SLACK, "ball gained %.3f J/kg of energy without a kick" % max_gain)
	_summary("rules always hold (court, floor, energy, time, determinism)", before, "(%d shots, worst energy gain %.4f J/kg)" % [all_cases.size(), max_gain])


func _energy(m) -> float:
	return 0.5 * (m.vx * m.vx + m.vy * m.vy + m.vz * m.vz) + BallModel.G * max(m.z, 0.0)


# --- 4 ---------------------------------------------------------------------

func _suite_playback() -> void:
	var before := failed
	var runs := 0
	for shot_name in ["lob", "contrapared", "double_wall", "smash_por_3"]:
		var s: Array = Shots.SHOTS[shot_name]
		var vel := BallModel.launch(s[0], s[1], s[2], s[3])
		var reference = BallModel.new()
		reference.reset(s[0], vel, s[4])
		reference.run_to_end()
		for fps in [30.0, 60.0, 144.0, 240.0, -1.0]:
			for scale in [1.0, 0.25, 0.1]:
				runs += 1
				_play_once(shot_name, s, vel, fps, scale, reference)
	_summary("ball.gd plays at real speed at 30/60/144/240 fps and with stutter", before, "(%d runs)" % runs)


func _play_once(shot_name: String, s: Array, vel: Array, fps: float, scale: float, reference) -> void:
	var label := "%s at %s fps, %sx" % [shot_name, "jittery" if fps < 0 else str(fps), scale]
	var ball = BallNode.new()
	var ends := [0]
	ball.point_over.connect(func(_r): ends[0] += 1)
	ball.play(s[0], vel, s[4])
	ball.time_scale = scale
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var game_time := 0.0
	var ticks := 0
	var drift := 0.0
	while not ball.model.is_done() and ticks < 200000:
		# fps < 0: frames between 4 ms and 50 ms, like a hitchy laptop
		var delta: float = rng.randf_range(0.004, 0.05) if fps < 0 else 1.0 / fps
		ball._physics_process(delta)
		game_time += delta * scale
		ticks += 1
		if not ball.model.is_done():
			drift = max(drift, abs(ball.model.t - game_time))
	for i in 5:
		ball._physics_process(1.0 / 60.0)
	_check(drift <= BallModel.DT + 1e-9, "%s: ball clock drifted %.4f s from game time" % [label, drift])
	_check(ball.model.path == reference.path, "%s: path differs from run_to_end" % label)
	_check(ends[0] == 1, "%s: point_over fired %d times" % [label, ends[0]])
	ball.free()


# --- 5 ---------------------------------------------------------------------

func _suite_controls() -> void:
	var before := failed
	Controls.register()
	Controls.register()   # twice on purpose: must not stack duplicate bindings
	var lab := []
	for action in Controls.ACTIONS:
		_check(InputMap.has_action(action), "action %s missing" % action)
		if action.begins_with("lab_"):
			lab.append(action)
	for action in Controls.ACTIONS:
		var a: Dictionary = Controls.ACTIONS[action]
		var wanted: int = a.get("keys", []).size() + a.get("buttons", []).size() + (1 if a.has("axis") else 0)
		_check(InputMap.action_get_events(action).size() == wanted, "%s has %d bindings, table says %d" % [action, InputMap.action_get_events(action).size(), wanted])
	for action in lab:
		var a: Dictionary = Controls.ACTIONS[action]
		_check(not a.get("keys", []).is_empty(), "%s has no key" % action)
		_check(not a.get("buttons", []).is_empty(), "%s has no gamepad button" % action)
		for k in a.get("keys", []):
			var e := InputEventKey.new()
			e.keycode = k
			e.pressed = true
			_check(_actions_for(e, lab) == [action], "key %s should trigger only %s, triggers %s" % [OS.get_keycode_string(k), action, _actions_for(e, lab)])
		for b in a.get("buttons", []):
			# pads 0 and 3: bindings must work on any pad, not just the first
			for device in [0, 3]:
				var e := InputEventJoypadButton.new()
				e.button_index = b
				e.pressed = true
				e.device = device
				_check(_actions_for(e, lab) == [action], "pad %d button %d should trigger only %s, triggers %s" % [device, b, action, _actions_for(e, lab)])
	# every key in the table triggers exactly one action across the whole
	# table, so WASD never fires a lab action and lab keys never move
	var all_actions := Controls.ACTIONS.keys()
	for action in all_actions:
		for k in Controls.ACTIONS[action].get("keys", []):
			var e := InputEventKey.new()
			e.keycode = k
			e.pressed = true
			_check(_actions_for(e, all_actions) == [action], "key %s should trigger only %s, triggers %s" % [OS.get_keycode_string(k), action, _actions_for(e, all_actions)])
	for action in all_actions:
		for b in Controls.ACTIONS[action].get("buttons", []):
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.pressed = true
			e.device = 2
			_check(_actions_for(e, all_actions) == [action], "button %d should trigger only %s, triggers %s" % [b, action, _actions_for(e, all_actions)])
	var swing: Dictionary = Controls.ACTIONS.swing
	_check(KEY_J in swing.keys and JOY_BUTTON_RIGHT_SHOULDER in swing.buttons and swing.axis[0] == JOY_AXIS_TRIGGER_RIGHT, "swing should be on J, the right bumper and the right trigger")
	_check(not (JOY_BUTTON_A in swing.get("buttons", [])), "A should stay free, it no longer swings")
	_check(JOY_BUTTON_START in Controls.ACTIONS.menu.buttons and KEY_ESCAPE in Controls.ACTIONS.menu.keys, "menu should be on Start and Esc")
	# menus pick with A and go back with B on any pad, added once even after two registers
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var e := InputEventJoypadButton.new()
		e.button_index = pair[1]
		e.pressed = true
		e.device = 2
		_check(e.is_action_pressed(pair[0]), "button %d should press %s" % [pair[1], pair[0]])
		var same := InputMap.action_get_events(pair[0]).filter(func(x): return x is InputEventJoypadButton and x.button_index == pair[1])
		_check(same.size() == 1, "%s has button %d %d times" % [pair[0], pair[1], same.size()])
	# WASD drives movement
	for case in [[KEY_A, "move_left"], [KEY_D, "move_right"], [KEY_W, "move_up"], [KEY_S, "move_down"]]:
		_check(case[1] in _key_actions(case[0]), "%s should be bound to %s" % [OS.get_keycode_string(case[0]), case[1]])
	# lab keeps off the face buttons, they belong to the player
	for action in lab:
		for b in Controls.ACTIONS[action].get("buttons", []):
			_check(b > JOY_BUTTON_Y, "%s uses face button %d, keep those for the player" % [action, b])
	# stick: past the deadzone moves, inside it doesn't. The left trigger is focus
	for case in [[JOY_AXIS_LEFT_X, -0.8, "move_left"], [JOY_AXIS_LEFT_X, 0.8, "move_right"], [JOY_AXIS_LEFT_Y, -0.8, "move_up"], [JOY_AXIS_LEFT_Y, 0.8, "move_down"], [JOY_AXIS_TRIGGER_LEFT, 1.0, "focus"], [JOY_AXIS_TRIGGER_RIGHT, 1.0, "swing"], [JOY_AXIS_RIGHT_X, -0.8, "aim_left"], [JOY_AXIS_RIGHT_X, 0.8, "aim_right"], [JOY_AXIS_RIGHT_Y, -0.8, "aim_up"], [JOY_AXIS_RIGHT_Y, 0.8, "aim_down"]]:
		for device in [1, 3]:
			var e := InputEventJoypadMotion.new()
			e.axis = case[0]
			e.axis_value = case[1]
			e.device = device
			_check(e.is_action_pressed(case[2]), "pad %d axis %s %.1f should press %s" % [device, case[0], case[1], case[2]])
			_check(_actions_for(e, all_actions) == [case[2]], "pad %d axis %s %.1f should press only %s, presses %s" % [device, case[0], case[1], case[2], _actions_for(e, all_actions)])
			e.axis_value = case[1] * 0.1
			_check(not e.is_action_pressed(case[2]), "axis inside the deadzone pressed %s" % case[2])
	_check(KEY_SHIFT in Controls.ACTIONS.focus.keys and JOY_AXIS_TRIGGER_LEFT == Controls.ACTIONS.focus.axis[0], "focus should be on Shift and the left trigger")
	Input.action_press("move_right", 1.0)
	Input.action_press("move_up", 1.0)
	var v := Controls.move_vector()
	_check(absf(v.length() - 1.0) < 1e-4 and v.x > 0.0 and v.y < 0.0, "full diagonal should be length 1 up-right, got %s" % v)
	Input.action_release("move_up")
	Input.action_press("move_right", Controls.STICK_DEADZONE * 0.5)
	_check(Controls.move_vector() == Vector2.ZERO, "small push inside the deadzone moved: %s" % Controls.move_vector())
	Input.action_release("move_right")
	_summary("controls: keyboard and gamepad bindings", before, "(%d actions)" % Controls.ACTIONS.size())


# --- 6 ---------------------------------------------------------------------

func _suite_player() -> void:
	var before := failed
	var p = PlayerNode.new()
	var dt := 1.0 / 60.0
	var lo := Vector2(PlayerNode.WALL_GAP, PlayerNode.WALL_GAP)
	var hi := Vector2(BallModel.W - PlayerNode.WALL_GAP, BallModel.NET_Y - PlayerNode.NET_GAP)
	# hold each direction for 4 s: never leaves the near half, never touches the net
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1)]:
		p.reset(Vector2(5.0, 5.0))
		var inside := true
		for i in 240:
			p.tick(dir, dt)
			inside = inside and p.px >= lo.x - 1e-9 and p.px <= hi.x + 1e-9 and p.py >= lo.y - 1e-9 and p.py <= hi.y + 1e-9
		_check(inside, "player left the near half holding %s: (%.2f, %.2f)" % [dir, p.px, p.py])
	# stick up (screen up) walks toward the net
	p.reset(Vector2(5.0, 3.0))
	for i in 30:
		p.tick(Vector2(0, -1), dt)
	_check(p.py > 3.0, "stick up should move toward the net, y went %.2f" % p.py)
	# top speed and acceleration: 1 s held right from x = 1
	p.reset(Vector2(1.0, 5.0))
	for i in 60:
		p.tick(Vector2.RIGHT, dt)
	var expected := PlayerNode.SPEED - PlayerNode.SPEED * PlayerNode.SPEED / (2.0 * PlayerNode.ACCEL)
	_check(absf(p.vel.length() - PlayerNode.SPEED) < 1e-6, "top speed %.2f, want %.2f" % [p.vel.length(), PlayerNode.SPEED])
	_check(absf((p.px - 1.0) - expected) < 0.1, "1 s of running covered %.2f m, want about %.2f" % [p.px - 1.0, expected])
	# a full diagonal is no faster than straight
	p.reset(Vector2(2.0, 2.0))
	for i in 60:
		p.tick(Vector2(1, -1), dt)
	_check(p.vel.length() <= PlayerNode.SPEED + 1e-6, "diagonal ran at %.2f m/s" % p.vel.length())
	# swing: live for SWING_ACTIVE, then a cooldown that blocks the next swing
	p.reset()
	_check(p.start_swing(), "first swing refused")
	_check(not p.start_swing(), "second swing started while the first is live")
	var live := 0.0
	while p.is_swinging():
		p.tick(Vector2.ZERO, 0.001)
		live += 0.001
	_check(absf(live - PlayerNode.SWING_ACTIVE) < 0.002, "swing was live %.3f s, want %.3f" % [live, PlayerNode.SWING_ACTIVE])
	_check(not p.start_swing(), "swing started during the cooldown")
	for i in int(PlayerNode.COOLDOWN / 0.001) + 2:
		p.tick(Vector2.ZERO, 0.001)
	_check(p.start_swing(), "swing refused after the cooldown")
	p.used_swing()
	_check(not p.is_swinging() and not p.start_swing(), "a connected swing should end and start the cooldown")
	# slow-mo: movement runs on delta, the swing on the clock (0.6x move, 0.4x world)
	p.reset(Vector2(1.0, 5.0))
	var q = PlayerNode.new()
	q.reset(Vector2(1.0, 5.0))
	p.start_swing()
	var ticks := 0
	while p.is_swinging() and ticks < 10000:
		p.drive(Vector2.RIGHT, 0.6 * 0.001, 0.4 * 0.001)
		q.drive(Vector2.RIGHT, 0.6 * 0.001)
		ticks += 1
	_check(absf(ticks * 0.4 * 0.001 - PlayerNode.SWING_ACTIVE) < 0.002, "slowed swing lasted %.3f s of world time, want %.3f" % [ticks * 0.4 * 0.001, PlayerNode.SWING_ACTIVE])
	_check(p.pos().distance_to(q.pos()) < 1e-9 and p.vel.distance_to(q.vel) < 1e-9, "the swing clock changed how the body moves")
	q.free()
	# reach and band
	p.reset(Vector2(5.0, 5.0))
	var mid :=(PlayerNode.BAND_LOW + PlayerNode.BAND_HIGH) * 0.5
	_check(p.can_reach(5.0 + PlayerNode.REACH * 0.99, 5.0, mid), "ball just inside reach not reachable")
	_check(not p.can_reach(5.0, 5.0 + PlayerNode.REACH * 1.01, mid), "ball just outside reach was reachable")
	_check(p.can_reach(5.0, 5.0, PlayerNode.BAND_LOW) and p.can_reach(5.0, 5.0, PlayerNode.BAND_HIGH), "band edges should count")
	_check(not p.can_reach(5.0, 5.0, PlayerNode.BAND_LOW - 0.01), "ball under the band was reachable")
	_check(not p.can_reach(5.0, 5.0, PlayerNode.BAND_HIGH + 0.01), "ball over the band was reachable")
	p.free()
	_summary("player: near half, speed, swing timing, reach and band", before)


# --- 7 ---------------------------------------------------------------------

func _suite_rally() -> void:
	var before := failed
	var returns := 0
	# every return from a grid over the near half, any aim, lands in
	for xi in 10:
		for yi in 10:
			for z in [PlayerNode.BAND_LOW, 1.0, PlayerNode.BAND_HIGH]:
				for aim_x in [5.0 - Planner.AIM_SPREAD, 5.0, 5.0 + Planner.AIM_SPREAD]:
					var c := [0.3 + xi * 1.04, 0.3 + yi * 1.03, z]
					var m = BallModel.new()
					m.reset(c, Planner.plan(c, aim_x), 1.0)
					m.run_to_end()
					returns += 1
					_check(m.end.begins_with("winner"), "return from %s aimed at x %.0f: %s (%s)" % [c, aim_x, m.end, m.describe()])
	var feeds := 0
	for feed_name in Rally.FEEDS:
		feeds += 1
		_rally_feed_rules(feed_name)
		_rally_return_feed(feed_name, true)
		_rally_return_feed(feed_name, false)
	_rally_tally()
	_summary("rally: mirrored feeds, receiver rules, legal returns, tally", before, "(%d returns, %d feeds)" % [returns, feeds])


func _rally_nodes() -> Array:
	var ball = BallNode.new()
	var p = PlayerNode.new()
	return [ball, p, Rally.new(ball, p)]


## a feed is the sim shot drawn turned around, and only playable once it's on our side
func _rally_feed_rules(feed_name: String) -> void:
	var n := _rally_nodes()
	var ball = n[0]
	var r = n[2]
	r.feed(feed_name)
	var s: Array = Shots.SHOTS[feed_name]
	var start: Vector3 = r.ball_court()
	_check(start.is_equal_approx(Vector3(BallModel.W - s[0][0], BallModel.L - s[0][1], s[0][2])), "%s should start mirrored on the far half, starts at %s" % [feed_name, start])
	var ok := true
	while not ball.model.is_done():
		ball.model.step()
		var b: Vector3 = r.ball_court()
		if r.ball_playable() and not ball.model.crossed():
			ok = false
		if ball.model.crossed() and not ball.model.is_done() and b.y > BallModel.NET_Y + 1e-9 and not ball.model.events.any(func(e): return e.kind == "net"):
			ok = false   # over the net means our half on screen
	_check(ok, "%s: playable while still on the feeder's side" % feed_name)
	ball.free()
	n[1].free()


## play the feed through ball.gd at 60 fps, stand where it's hittable and swing
## on time. after_bounce: wait for the bounce on our side, else volley it
func _rally_return_feed(feed_name: String, after_bounce: bool) -> void:
	var n := _rally_nodes()
	var ball = n[0]
	var p = n[1]
	var r = n[2]
	r.feed(feed_name)
	# look ahead on a copy to find the first hittable moment
	var ahead = BallModel.new()
	var s: Array = Shots.SHOTS[feed_name]
	ahead.reset(s[0], BallModel.launch(s[0], s[1], s[2], s[3]), s[4])
	var hit_t := -1.0
	var spot := Vector2.ZERO
	while not ahead.is_done():
		ahead.step()
		var bounced: bool = ahead.events.any(func(e): return e.kind == "floor" and e.detail == "far")
		if ahead.crossed() and not ahead.is_done() and (bounced or not after_bounce) \
				and ahead.z >= PlayerNode.BAND_LOW and ahead.z <= PlayerNode.BAND_HIGH:
			hit_t = ahead.t
			spot = Vector2(BallModel.W - ahead.x, BallModel.L - ahead.y)
			break
	var label := "%s (%s)" % [feed_name, "after the bounce" if after_bounce else "volley"]
	if hit_t < 0.0:
		_check(after_bounce, "%s: never hittable" % label)
		ball.free()
		p.free()
		return
	p.reset(Vector2(clampf(spot.x, 0.3, 9.7), clampf(spot.y, 0.3, 9.6)))
	var ends := []
	ball.point_over.connect(func(res): ends.append(res))
	var swung := false
	for i in 1200:
		if not swung and ball.model.t >= hit_t - PlayerNode.SWING_ACTIVE * 0.5:
			swung = p.start_swing()
		p.tick(Vector2.ZERO, 1.0 / 60.0)
		ball._physics_process(1.0 / 60.0)
		if ends.size() > 0:
			break
	_check(r.returned == 1, "%s: not returned (stood at %s, ball at %.2fs)" % [label, spot, hit_t])
	_check(ends.size() == 1 and ends[0].begins_with("winner"), "%s: return ended %s" % [label, ends])
	_check(r.returns_in == r.returned and r.return_errors == 0, "%s: tally in %d errors %d" % [label, r.returns_in, r.return_errors])
	ball.free()
	p.free()


func _rally_tally() -> void:
	# left alone: a feed that goes out is a good leave, one that stays in is a miss
	for case in [["too_long", "good_leaves"], ["lob", "missed"], ["double_wall", "missed"]]:
		var n := _rally_nodes()
		var ball = n[0]
		var r = n[2]
		r.feed(case[0])
		for i in 1200:
			ball._physics_process(1.0 / 60.0)
			if r.state == "idle":
				break
		_check(r.get(case[1]) == 1 and r.fed == 1 and r.returned == 0, "%s left alone should count 1 %s, got missed %d leaves %d" % [case[0], case[1], r.missed, r.good_leaves])
		# a swing far from the ball does nothing
		ball.free()
		n[1].free()
	var n := _rally_nodes()
	n[1].reset(Vector2(9.0, 1.0))
	n[2].feed("lob")
	n[1].start_swing()
	for i in 600:
		n[1].tick(Vector2.ZERO, 1.0 / 60.0)
		if not n[1].is_swinging():
			n[1].start_swing()
		n[0]._physics_process(1.0 / 60.0)
	_check(n[2].returned == 0, "swinging out of reach returned the ball")
	n[0].free()
	n[1].free()


func _key_actions(k: Key) -> Array:
	var hit := []
	for action in Controls.ACTIONS:
		if k in Controls.ACTIONS[action].get("keys", []):
			hit.append(action)
	return hit


func _actions_for(e: InputEvent, actions: Array) -> Array:
	var hit := []
	for action in actions:
		if e.is_action_pressed(action):
			hit.append(action)
	return hit


# --- 8 ---------------------------------------------------------------------

func _suite_match() -> void:
	var before := failed
	_match_far_body()
	var lobs := _match_lobs()
	_match_shot_choice()
	_match_points()
	var rate := _match_return_rate()
	_match_rush_rule()
	var stats := _match_long_run()
	var tagged := _match_overlay()
	stats += ", %d hits tagged" % tagged
	var rings := _match_last_bounce()
	_match_aim_spot()
	_summary("match: far half, lobs, shot choice, scoring, serves, opponent vs opponent, last bounce, aim line", before,
		"(%d lobs, opponent returns %d%% of your drives, %s, %d last bounces predicted)" % [lobs, roundi(rate * 100.0), stats, rings])


## the last-bounce ring: shots from both halves play out with nobody swinging. The
## ring must appear exactly when the ball ends on a second bounce, and the spot and
## time it gave while the ball was still in the air must match where it landed
func _match_last_bounce() -> int:
	var predicted := 0
	var other := 0
	for side in ["near", "far"]:
		for xi in 5:
			for yi in 4:
				for shot in ["drive", "lob", "hard", "net", "long", "hot"]:
					var n := _match_nodes()
					var r = n[3]
					r.state = "play"
					var c := [1.0 + xi * 2.0, 1.0 + yi * 2.5, 1.0]
					var vel: Array
					match shot:
						"drive":
							vel = Planner.plan(c, 2.0 + xi * 1.5)
						"lob":
							vel = Planner.plan_lob(c, 2.0 + xi * 1.5)
						# balls that never reach a second bounce: into the net, onto
						# their glass before bouncing, over the side wall after one
						"net":
							vel = BallModel.launch(c, 12.0, 2.0, [5.0, 12.0])
						"long":
							vel = BallModel.launch(c, 28.0, 8.0, [5.0, 19.0])
						"hot":
							vel = BallModel.launch(c, 30.0, 18.0, [9.5, 15.0])
						_:
							vel = Planner.plan(c, 8.0 - xi * 1.5, Planner.TARGET_DEPTH, 22.0)
					r._launch(side, c, vel)
					var first := {}
					var early := false
					for i in 3600:
						n[0]._physics_process(1.0 / 60.0)
						var lb: Dictionary = r.last_bounce()
						if not lb.is_empty():
							if first.is_empty():
								first = lb.duplicate()
								first.t = n[0].model.t + lb.eta
							_check(lb.side == r.receiver(), "the ring named %s, the receiver is %s" % [lb.side, r.receiver()])
							_check(lb.at.distance_to(first.at) < 1e-9, "the landing spot moved while the ball flew")
							_check(absf(n[0].model.t + lb.eta - first.t) < 1e-9, "the landing time drifted while the ball flew")
						var floors: int = n[0].model.events.filter(func(e): return e.kind == "floor" and e.detail == "far").size()
						early = early or (floors == 0 and not lb.is_empty())
						if r.state == "over":
							break
					_check(not early, "a ring showed before the first bounce")
					var landed: Array = n[0].model.events.filter(func(e): return e.kind == "floor" and e.detail == "far")
					if n[0].model.end == "winner: second bounce" and landed.size() == 2:
						_check(not first.is_empty(), "%s %s from %s: ended on a second bounce, the ring never showed" % [side, shot, c])
						if not first.is_empty():
							var at: Vector2 = Rules.to_court(side, landed[1].x, landed[1].y)
							_check(first.at.distance_to(at) < 1e-9, "%s %s from %s: ring at %s, landed at %s" % [side, shot, c, first.at, at])
							_check(absf(first.t - landed[1].t) < 1e-9, "%s %s from %s: ring said t %.4f, landed at %.4f" % [side, shot, c, first.t, landed[1].t])
							predicted += 1
					else:
						other += 1
						_check(first.is_empty(), "%s %s from %s: the ring showed for a ball that ended '%s'" % [side, shot, c, n[0].model.end])
					_match_free(n)
	_check(predicted >= 20, "only %d of the shots ended on a second bounce, the test isn't covering the ring" % predicted)
	_check(other >= 1, "every shot ended on a second bounce, the no-ring case isn't covered")
	return predicted


# --- 9 ---------------------------------------------------------------------

func _suite_focus() -> void:
	var before := failed
	var dt := 1.0 / 60.0
	var f = Focus.new()
	# not held: nothing changes, the world runs at full speed
	for i in 120:
		f.update(false, dt)
	_check(not f.engaged and f.meter == 1.0 and f.world_scale() == 1.0 and f.player_scale() == 1.0, "idle focus changed something")
	# held: drains in SECONDS, then locks
	var held_s := 0.0
	while f.engaged or held_s == 0.0:
		f.update(true, dt)
		held_s += dt
		if held_s > Focus.SECONDS * 2.0:
			break
	_check(absf(held_s - Focus.SECONDS) < 0.1, "a full meter lasted %.2f s, want %.2f" % [held_s, Focus.SECONDS])
	_check(f.meter == 0.0 and f.locked and not f.engaged, "a dry meter should lock")
	for i in 60:
		f.update(true, dt)
	_check(not f.engaged, "slow-mo came back while the button was still held")
	# slowed: the world is slower than you, you are slower than normal
	var g = Focus.new()
	for i in 30:
		g.update(true, dt)
	_check(g.engaged and absf(g.world_scale() - Focus.WORLD_SCALE) < 1e-9 and absf(g.player_scale() - Focus.PLAYER_SCALE) < 1e-9, "slow-mo didn't reach its scales: world %.3f, you %.3f" % [g.world_scale(), g.player_scale()])
	_check(g.world_scale() < g.player_scale() and g.player_scale() < 1.0, "you should be faster than the world but slower than normal")
	# letting go ends it and refills in REFILL seconds
	var used: float = g.meter
	var refill_s := 0.0
	while g.meter < 1.0 and refill_s < Focus.REFILL * 2.0:
		g.update(false, dt)
		refill_s += dt
	_check(not g.engaged and g.world_scale() < 1.0 + 1e-9, "slow-mo stayed on after letting go")
	_check(absf(refill_s - (1.0 - used) * Focus.REFILL) < 0.1, "refill took %.2f s, want %.2f" % [refill_s, (1.0 - used) * Focus.REFILL])
	for i in 30:
		g.update(false, dt)
	_check(g.blend == 0.0 and g.world_scale() == 1.0, "the world didn't return to full speed")
	# after running dry: let go, wait for MIN_START, then it works again, not before
	var h = Focus.new()
	h.meter = 0.0
	h.locked = true
	h.update(true, dt)
	_check(not h.engaged, "a locked meter engaged")
	h.update(false, dt)
	h.update(true, dt)
	_check(not h.engaged, "engaged with the meter under MIN_START")
	for i in int(Focus.MIN_START * Focus.REFILL / dt) + 2:
		h.update(false, dt)
	h.update(true, dt)
	_check(h.engaged and not h.locked, "refilled past MIN_START and let go, but it won't engage")
	# invariants over a random hold pattern
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var k = Focus.new()
	var ok := true
	for i in 20000:
		k.update(rng.randf() < 0.5 if i % 60 == 0 else k.engaged or rng.randf() < 0.02, dt)
		ok = ok and k.meter >= 0.0 and k.meter <= 1.0 and k.blend >= 0.0 and k.blend <= 1.0 and k.world_scale() >= Focus.WORLD_SCALE - 1e-9
	_check(ok, "meter or blend left its range under a random hold pattern")
	_summary("focus: slow-mo meter, scales, lock and refill", before)


## a match with no brains: the test drives everything
func _match_nodes() -> Array:
	var ball = BallNode.new()
	var near = PlayerNode.new()
	var far = PlayerNode.new()
	return [ball, near, far, Rules.new(ball, near, far)]


## the aim line on screen reads Planner.aim_x. Your real shot has to land there:
## same sideways spot (within 0.5 m), on the far half, for every stick position
func _match_aim_spot() -> void:
	_check(is_equal_approx(Planner.aim_x(0.0), 5.0), "no stick should aim at the center line")
	_check(is_equal_approx(Planner.aim_x(-1.0), 5.0 - Planner.AIM_SPREAD) and is_equal_approx(Planner.aim_x(1.0), 5.0 + Planner.AIM_SPREAD), "full stick should aim AIM_SPREAD off center")
	_check(is_equal_approx(Planner.aim_x(3.0), Planner.aim_x(1.0)) and is_equal_approx(Planner.aim_x(-3.0), Planner.aim_x(-1.0)), "a stick past 1 should not aim further")
	_match_aim_choice()
	for stick in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var n := _match_nodes()
		var r = n[3]
		r.state = "play"
		r._launch("far", [5.0, 3.0, 1.0], Planner.plan([5.0, 3.0, 1.0], 5.0))
		var hit := false
		for i in 600:
			if r.playable_for("near"):
				# put the body under the ball so the swing is in reach
				var b: Vector3 = r.ball_court()
				n[1].reset(Vector2(b.x, minf(b.y, BallModel.NET_Y - 0.5)))
				if not n[1].is_swinging():
					n[1].start_swing()
			n[1].tick(Vector2.ZERO, 1.0 / 60.0)
			r.aim = stick
			n[0]._physics_process(1.0 / 60.0)
			if r.last_hitter == "near":
				hit = true
				break
			if r.state == "over":
				break
		_check(hit, "stick %.1f: the swing never connected" % stick)
		if hit:
			var land := _first_bounce(n[0])
			_check(land.y > BallModel.NET_Y, "stick %.1f: the shot landed on your own half, %s" % [stick, land])
			_check(absf(land.x - Planner.aim_x(stick)) < 0.5, "stick %.1f: aim line says x %.2f, the shot landed at x %.2f" % [stick, Planner.aim_x(stick), land.x])
		_match_free(n)


## the right stick: what the swing does for each direction, and the contrapared
## has to be a real shot (our glass first, over the net, in their box)
func _match_aim_choice() -> void:
	var rest := Planner.aim_choice(5.0, 2.0, 0.5, Vector2.ZERO)
	_check(rest.kind == "drive" and is_equal_approx(rest.x, Planner.aim_x(0.5)), "a resting right stick should keep the left stick nudge")
	var fwd := Planner.aim_choice(5.0, 2.0, 0.0, Vector2(sin(deg_to_rad(36.0)), cos(deg_to_rad(36.0))))
	_check(fwd.kind == "drive" and fwd.land.is_equal_approx(Vector2(8.5, Planner.TARGET_DEPTH)), "right stick 36 degrees right should lock the deep-right zone, got %s" % fwd.land)
	var side := Planner.aim_choice(5.0, 2.0, 0.0, Vector2(1.0, 0.0))
	_check(side.kind == "drive" and side.land.is_equal_approx(Vector2(8.5, 12.0)) and is_equal_approx(side.pace, 11.0), "right stick straight right should lock the short-right zone, got %s" % side.land)
	var back := Planner.aim_choice(5.0, 2.0, 0.0, Vector2(0.0, -1.0))
	_check(back.kind == "contra" and is_equal_approx(back.to.y, 0.0) and back.land.is_equal_approx(Vector2(5.0, Planner.CONTRA_DEPTH)), "right stick straight back near the glass should play the glass")
	var far_back := Planner.aim_choice(5.0, Planner.CONTRA_MAX_Y + 0.5, 0.0, Vector2(0.0, -1.0))
	_check(far_back.kind == "drive", "right stick back with the glass out of reach should stay a drive")
	var edge := Planner.aim_choice(5.0, 2.0, 0.0, Vector2(sin(deg_to_rad(65.0)), -cos(deg_to_rad(65.0))))
	_check(edge.kind == "drive", "65 degrees off straight back is outside the glass wedge")
	var inside := Planner.aim_choice(5.0, 2.0, 0.0, Vector2(sin(deg_to_rad(55.0)), -cos(deg_to_rad(55.0))))
	_check(inside.kind == "contra", "55 degrees off straight back is inside the glass wedge")
	_match_zones()
	_match_aim_memory()
	_match_drive_zones()
	# the shot itself, from a grid of contacts near your glass
	var made := 0
	var tries := 0
	var started := Time.get_ticks_msec()
	for y in [0.6, 1.5, 2.5]:
		for z in [0.6, 1.0, 1.5]:
			for x in [3.0, 5.0, 7.0]:
				for gx in [1.5, 5.0, 8.5]:
					tries += 1
					var c := [x, y, z]
					var vel := Planner.plan_contrapared(c, gx)
					if vel.is_empty():
						continue
					made += 1
					var m = BallModel.new()
					m.reset(c, vel, 1.0)
					m.run_to_end()
					_check(m.end == "winner: second bounce", "contrapared from %s aimed at x %.1f ended %s" % [c, gx, m.end])
					var first_wall := ""
					for e in m.events:
						if e.kind == "glass" or e.kind == "mesh":
							first_wall = "%s %s" % [e.kind, e.detail]
							break
					_check(first_wall == "glass back", "contrapared from %s touched %s first" % [c, first_wall])
					for e in m.events:
						if e.kind == "floor" and e.detail == "far":
							_check(absf(e.x - gx) < 1.0, "contrapared from %s aimed at x %.1f landed at x %.2f" % [c, gx, e.x])
							break
	var ms := float(Time.get_ticks_msec() - started) / tries
	_check(made >= tries * 0.8, "only %d of %d contrapared plans worked" % [made, tries])
	_check(ms < 80.0, "a contrapared plan takes %.0f ms, too slow for a swing" % ms)
	print("   contrapared: %d of %d plans, %.0f ms each" % [made, tries, ms])
	# a real swing: a deep lob bounces near your glass. Stick back plays the glass,
	# stick at rest plays a normal drive
	for back_stick in [true, false]:
		var n := _match_nodes()
		var r = n[3]
		r.state = "play"
		var c := [5.0, 3.0, 1.0]
		r._launch("far", c, Planner.plan_lob(c, 5.0))
		var hit := false
		for i in 900:
			if r.playable_for("near"):
				var b: Vector3 = r.ball_court()
				if b.y <= Planner.CONTRA_MAX_Y:
					n[1].reset(Vector2(b.x, b.y))
					if not n[1].is_swinging():
						n[1].start_swing()
			n[1].tick(Vector2.ZERO, 1.0 / 60.0)
			r.aim_dir = Vector2(0.0, -1.0) if back_stick else Vector2.ZERO
			n[0]._physics_process(1.0 / 60.0)
			if r.last_hitter == "near":
				hit = true
				break
			if r.state == "over":
				break
		_check(hit, "back stick %s: the swing near the glass never connected" % back_stick)
		if hit:
			var m = n[0].model.clone()
			m.run_to_end()
			var first_wall := ""
			for e in m.events:
				if e.kind == "glass" or e.kind == "mesh":
					first_wall = "%s %s%s" % [e.kind, e.detail, " (ours)" if e.y < BallModel.NET_Y else ""]
					break
			# the log record of the swing: what you pushed, the zone, and where you stood
			var rec: Dictionary = r.hits.back()
			_check(rec.side == "near" and rec.shot_type == ("contra" if back_stick else "nudge"), "the hit record says %s for back stick %s" % [rec.shot_type, back_stick])
			_check(rec.stick.is_equal_approx(Vector2(0.0, -1.0) if back_stick else Vector2.ZERO), "the hit record kept the stick %s" % rec.stick)
			_check(rec.you.distance_to(n[1].pos()) < 0.05, "the hit record has you at %s, you are at %s" % [rec.you, n[1].pos()])
			if back_stick:
				_check(rec.zone.is_equal_approx(Vector2(5.0, Planner.CONTRA_DEPTH)), "the hit record zone for a straight back push is %s" % rec.zone)
			else:
				_check(rec.zone.is_equal_approx(Vector2(Planner.aim_x(0.0), Planner.TARGET_DEPTH)), "the hit record zone for a resting stick is %s" % rec.zone)
			if back_stick:
				_check(first_wall == "glass back (ours)" and m.end == "winner: second bounce", "stick back should play our glass and land in, got %s, %s" % [first_wall, m.end])
			else:
				_check(first_wall != "glass back (ours)", "a resting stick should not play our own glass")
		_match_free(n)
	# from too high or too far out nothing works, and the swing falls back to a drive
	_check(Planner.plan_contrapared([5.0, 9.0, 1.0], 5.0).is_empty(), "a contrapared from the net can't exist")


## the zone targets: locked on each zone, a straight slide between, clamped at the ends
func _match_zones() -> void:
	var zones: Array = Planner.DRIVE_ZONES
	for z in zones:
		for off in [-Planner.ZONE_LOCK, 0.0, Planner.ZONE_LOCK]:
			var t := Planner.zone_target(z[0] + off, zones)
			var inside: bool = z[0] + off >= zones[0][0] and z[0] + off <= zones[zones.size() - 1][0]
			if inside:
				_check((t[0] as Vector2).is_equal_approx(z[1]), "%.0f degrees off zone %.0f should stay locked on it, got %s" % [off, z[0], t[0]])
	_check((Planner.zone_target(-170.0, zones)[0] as Vector2).is_equal_approx(zones[0][1]) and (Planner.zone_target(170.0, zones)[0] as Vector2).is_equal_approx(zones[zones.size() - 1][1]), "past the outer zones the target should clamp")
	# between two zones the target moves one way, never jumps, and never leaves the box of the two spots
	var prev := Vector2(-1.0, -1.0)
	var worst := 0.0
	var a: float = zones[0][0]
	while a <= zones[zones.size() - 1][0]:
		var spot: Vector2 = Planner.zone_target(a, zones)[0]
		if prev.x >= 0.0:
			worst = maxf(worst, spot.distance_to(prev))
			_check(spot.x >= prev.x - 1e-6, "the target went backward at %.1f degrees" % a)
		prev = spot
		a += 0.5
	_check(worst < 0.5, "the target jumped %.2f m between half degree steps" % worst)
	# the same slide for the contrapared zones
	var cz: Array = Planner.CONTRA_ZONES
	_check((Planner.zone_target(0.0, cz)[0] as Vector2).is_equal_approx(Vector2(5.0, Planner.CONTRA_DEPTH)), "straight back should lock the center contrapared zone")
	var mid: Vector2 = Planner.zone_target(35.0 - Planner.ZONE_LOCK - 2.0, cz)[0]
	_check(mid.x > 5.0 and mid.x < 8.0, "between the center and right contrapared zones should slide, got %s" % mid)


## a flick still counts for a moment after the thumb lets go
func _match_aim_memory() -> void:
	var m = Aim.new()
	var dt := 1.0 / 60.0
	_check(m.update(Vector2.ZERO, dt) == Vector2.ZERO, "a stick that never moved should give no aim")
	var flick := Vector2(0.6, 0.8)
	_check(m.update(flick, dt) == flick, "a pushed stick should pass straight through")
	var held := 0
	for i in 20:
		if m.update(Vector2.ZERO, dt) == flick:
			held += 1
	_check(absf(held * dt - Aim.MEMORY) <= dt * 1.5, "the flick should be remembered %.2f s, was %.2f s" % [Aim.MEMORY, held * dt])
	_check(m.update(Vector2.ZERO, dt) == Vector2.ZERO, "after the memory runs out the aim should be empty")
	# a new push replaces it, a small one inside the rest radius doesn't
	var other := Vector2(-1.0, 0.0)
	m.update(flick, dt)
	m.update(other, dt)
	_check(m.update(Vector2.ZERO, dt) == other, "the newest push should be the one remembered")
	m.update(Vector2(0.1, 0.1), Aim.MEMORY * 2.0)
	_check(m.update(Vector2(0.1, 0.1), dt) == Vector2.ZERO, "a push inside the rest radius should not count")


## drives to each zone through the real model: in, near the zone spot, from all over your half
func _match_drive_zones() -> void:
	var tries := 0
	var good := 0
	for z in Planner.DRIVE_ZONES:
		var spot: Vector2 = z[1]
		for x in [1.5, 3.5, 5.0, 6.5, 8.5]:
			for y in [1.0, 3.0, 5.5, 8.0]:
				tries += 1
				var c := [x, y, 1.0]
				var m = BallModel.new()
				m.reset(c, Planner.plan_to(c, spot, z[2]), 1.0)
				var land := Vector2(-1.0, -1.0)
				while not m.is_done() and land.x < 0.0:
					m.step()
					for e in m.events:
						if e.kind == "floor":
							land = Vector2(e.x, e.y)
							break
				if land.x >= 0.0 and land.y > BallModel.NET_Y and absf(land.x - spot.x) < 1.2 and absf(land.y - spot.y) < 2.0:
					good += 1
				else:
					print("   zone %s from %s landed %s" % [spot, c, land])
	_check(good >= tries * 0.95, "only %d of %d zone drives landed near their zone" % [good, tries])


func _match_free(n: Array) -> void:
	n[3].brains.clear()
	n[0].free()
	n[1].free()
	n[2].free()


## run the scene loop at 60 fps: brains, rules, ball. Stops when the point ends
func _match_play_point(n: Array, brains: Array, max_ticks := 3600) -> void:
	for i in max_ticks:
		for b in brains:
			b.tick(1.0 / 60.0)
		for side in ["near", "far"]:
			if not n[3].brains.has(side):
				n[3].bodies[side].tick(Vector2.ZERO, 1.0 / 60.0)
		n[3].tick(1.0 / 60.0)
		n[0]._physics_process(1.0 / 60.0)
		if n[3].state == "over":
			return


func _match_far_body() -> void:
	var p = PlayerNode.new()
	p.far = true
	var lo := Vector2(PlayerNode.WALL_GAP, BallModel.NET_Y + PlayerNode.NET_GAP)
	var hi := Vector2(BallModel.W - PlayerNode.WALL_GAP, BallModel.L - PlayerNode.WALL_GAP)
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1), Vector2(-1, -1)]:
		p.reset(Vector2(5.0, 15.0))
		var inside := true
		for i in 240:
			p.drive(dir, 1.0 / 60.0)
			inside = inside and p.px >= lo.x - 1e-9 and p.px <= hi.x + 1e-9 and p.py >= lo.y - 1e-9 and p.py <= hi.y + 1e-9
		_check(inside, "far body left the far half driving %s: (%.2f, %.2f)" % [dir, p.px, p.py])
	p.free()


## lobs from anywhere on the hitter's half land in and pass over a player at the net
func _match_lobs() -> int:
	var count := 0
	for xi in 6:
		for yi in 6:
			for z in [PlayerNode.BAND_LOW, PlayerNode.BAND_HIGH]:
				for aim_x in [1.0, 5.0, 9.0]:
					var c := [0.5 + xi * 1.8, 0.5 + yi * 1.6, z]
					var m = BallModel.new()
					m.reset(c, Planner.plan_lob(c, aim_x), 1.0)
					var low_over_net_player := false
					while not m.is_done():
						m.step()
						var near_net: bool = m.y > BallModel.NET_Y + PlayerNode.NET_GAP and m.y < BallModel.NET_Y + Opponent.LOB_WHEN
						if near_net and m.z <= PlayerNode.BAND_HIGH and not m.events.any(func(e): return e.kind == "floor"):
							low_over_net_player = true
					count += 1
					_check(m.end.begins_with("winner"), "lob from %s aimed at x %.0f: %s (%s)" % [c, aim_x, m.end, m.describe()])
					_check(not low_over_net_player, "lob from %s aimed at x %.0f is reachable from the net" % [c, aim_x])
	return count


## first bounce of the ball in the air, court coordinates
func _first_bounce(ball) -> Vector2:
	var m = ball.model.clone()
	m.events.clear()
	while not m.is_done() and m.events.is_empty():
		m.step()
		m.events = m.events.filter(func(e): return e.kind == "floor")
	if m.events.is_empty():
		return Vector2(-1, -1)
	return ball.world(m.events[0].x, m.events[0].y)


func _match_shot_choice() -> void:
	# you near the net: lob. you at the back: drive. Either way away from you
	for case in [[Vector2(2.0, 8.5), true], [Vector2(8.0, 8.0), true], [Vector2(2.0, 2.0), false], [Vector2(8.0, 3.0), false]]:
		var n := _match_nodes()
		var opp = Opponent.new(n[3], "far", 3)
		n[1].reset(case[0])
		n[2].reset(Vector2(5.0, 16.0))
		var contact := Rules.to_model("far", Vector3(5.0, 16.0, 1.0))
		var vel: Array = opp.choose_shot(contact)
		_check(opp.last_was_lob == case[1], "you at %s: lob %s, want %s" % [case[0], opp.last_was_lob, case[1]])
		n[3]._launch("far", contact, vel)
		var land := _first_bounce(n[0])
		_check(land.y > 0.0 and land.y < BallModel.NET_Y, "shot from the far half should land on yours, landed %s" % land)
		_check((land.x - 5.0) * (case[0].x - 5.0) < 0.0, "you at x %.0f, the shot landed at x %.1f: same side as you" % [case[0].x, land.x])
		_match_free(n)


func _match_points() -> void:
	var n := _match_nodes()
	var r = n[3]
	var opp = Opponent.new(r, "far", 5)
	# point 1: you serve, it returns, you don't move: its point
	_check(r.state == "serve" and r.server == "near" and r.receiver() == "", "a match starts with your serve")
	_check(r.serve() and r.state == "play" and r.last_hitter == "near" and r.receiver() == "far", "serve should put the ball in play for the far side")
	var land := _first_bounce(n[0])
	_check(land.y > BallModel.NET_Y and land.y < BallModel.NET_Y + BallModel.SERVICE_FROM_NET and land.x < 5.0, "your first serve (from the right) should land in their left box, landed %s" % land)
	_check(not r.serve(), "a second serve during the point was accepted")
	_match_play_point(n, [opp])
	_check(r.state == "over" and r.score.far == 1 and r.score.near == 0 and r.rally_len == 2, "standing still after your serve should lose the point 0-1 after 2 hits, got %s, %d hits, %s" % [r.score, r.rally_len, r.last])
	# point 2: it serves by itself from its right, diagonally into your box
	r.next_point()
	_check(r.server == "far" and r.state == "serve", "the serve should change sides")
	var served := false
	for i in 120:
		opp.tick(1.0 / 60.0)
		r.tick(1.0 / 60.0)
		if r.state == "play":
			served = true
			break
	_check(served and r.last_hitter == "far", "the opponent never served")
	land = _first_bounce(n[0])
	_check(land.y > BallModel.NET_Y - BallModel.SERVICE_FROM_NET and land.y < BallModel.NET_Y and land.x < 5.0, "its serve from its left (second point) should land in your left box, landed %s" % land)
	_match_play_point(n, [opp])
	_check(r.score.far == 2 and r.points == 2, "not returning the serve should lose the point, score %s" % r.score)
	# an error goes to the other side: you hit it long into their back glass
	r.next_point()
	r.serve()
	r._launch("near", [5.0, 5.0, 1.0], BallModel.launch([5.0, 5.0, 1.0], 30.0, 5.0, [5.0, 20.0]))
	_match_play_point(n, [])
	_check(r.score.far == 3 and r.last.contains("out"), "your ball out should be their point, got %s, %s" % [r.score, r.last])
	# a winner goes to the hitter: it hits one you don't touch
	r.next_point()
	r._launch("far", [5.0, 3.0, 1.0], Planner.plan([5.0, 3.0, 1.0], 5.0))
	_match_play_point(n, [])
	_check(r.score.far == 4 and r.last.begins_with("Opponent won"), "their ball in should be their point, got %s, %s" % [r.score, r.last])
	# you swing out of reach: nothing happens. In reach: it goes back
	r.next_point()
	r._launch("far", [5.0, 3.0, 1.0], Planner.plan([5.0, 3.0, 1.0], 5.0))
	n[1].reset(Vector2(9.5, 0.5))
	var hits := 0
	for i in 600:
		if not n[1].is_swinging():
			n[1].start_swing()
		n[1].tick(Vector2.ZERO, 1.0 / 60.0)
		n[0]._physics_process(1.0 / 60.0)
		if r.last_hitter == "near":
			hits += 1
			break
		if r.state == "over":
			break
	_check(hits == 0, "a swing out of reach returned the ball")
	_match_free(n)


## you hit drives from all over your half to every aim, the opponent starts at home
func _match_return_rate() -> float:
	var tries := 0
	var back := 0
	for xi in 5:
		for yi in 4:
			for aim in [-1.0, 0.0, 1.0]:
				var n := _match_nodes()
				var r = n[3]
				var opp = Opponent.new(r, "far", xi * 100 + yi * 10 + int(aim))
				r.state = "play"
				n[2].reset(opp.home())
				var c := [1.0 + xi * 2.0, 1.0 + yi * 2.5, 1.0]
				r._launch("near", c, Planner.plan(c, 5.0 + aim * Planner.AIM_SPREAD))
				_match_play_point(n, [opp])
				tries += 1
				if r.rally_len >= 2:
					back += 1
					_check(r.last_hitter == "far", "the opponent hit the ball twice in a row")
				_match_free(n)
	var rate := float(back) / tries
	_check(rate >= 0.6, "the opponent returns only %d%% of your drives" % roundi(rate * 100.0))
	_check(rate < 1.0, "the opponent returns every drive, you can't win a point")
	return rate


## Session 19 camping fix: a deep incoming ball is let to bounce (the brain stays
## back, no net volley); a short one draws it forward. Drives the RUSH_Y gate.
func _match_rush_rule() -> void:
	# deep drive: first far-side bounce is well behind RUSH_Y, so no volley
	var n := _match_nodes()
	var r = n[3]
	var opp = Opponent.new(r, "far", 7)
	r.state = "play"
	n[2].reset(opp.home())
	r._launch("near", [5.0, 2.0, 1.0], Planner.plan([5.0, 2.0, 1.0], 5.0))
	for i in 90:
		n[0]._physics_process(1.0 / 60.0)
		if n[0].model.crossed():
			break
	_check(opp.first_land_y() >= Opponent.RUSH_Y, "a deep drive should read as deep")
	opp.make_plan()
	_check(opp.stand.y > BallModel.NET_Y + 6.0, "deep drive: plans to stand at y %.2f, should stay back" % opp.stand.y)
	_match_free(n)
	# short ball: first far-side bounce is inside RUSH_Y, so it may rush the net
	n = _match_nodes()
	r = n[3]
	opp = Opponent.new(r, "far", 7)
	r.state = "play"
	n[2].reset(opp.home())
	r._launch("near", [5.0, 1.0, 1.0], Planner.plan_to([5.0, 1.0, 1.0], Vector2(5.0, 12.0), 11.0))
	for i in 90:
		n[0]._physics_process(1.0 / 60.0)
		if n[0].model.crossed():
			break
	_check(opp.first_land_y() < Opponent.RUSH_Y, "a short ball should read as short")
	opp.make_plan()
	_check(opp.stand.y < BallModel.NET_Y + 6.0, "short ball: plans to stand at y %.2f, should come forward" % opp.stand.y)
	_match_free(n)


## the data behind the overlay and the log, from 40 points of opponent vs opponent
func _match_overlay() -> int:
	# shot kinds from contact and landing x (court), center line at 5
	_check(Rules.shot_kind(8.0, 1.5) == "cross" and Rules.shot_kind(2.0, 8.5) == "cross", "a diagonal shot isn't cross")
	_check(Rules.shot_kind(8.0, 8.5) == "line" and Rules.shot_kind(2.0, 1.5) == "line", "a straight shot isn't line")
	_check(Rules.shot_kind(8.0, 5.5) == "mid" and Rules.shot_kind(5.2, 1.5) == "line", "mid or a shot from the center is wrong")
	_check(Rules.strain_name(0.0) == "easy" and Rules.strain_name(0.3) == "working" and Rules.strain_name(0.8) == "stretched", "strain names are wrong")
	var n := _match_nodes()
	var r = n[3]
	var near = Opponent.new(r, "near", 3)
	var far = Opponent.new(r, "far", 4)
	var tagged := 0
	var near_hits := 0
	var near_net := 0
	var near_won := 0
	var causes := 0
	while r.points < 40:
		_match_play_point(n, [near, far], 7200)
		for h in r.hits:
			tagged += 1
			if h.kind == "serve":
				_check(h.came == "serve" and not h.net and not h.lob, "a serve was tagged as a rally shot")
				continue
			_check(h.kind == Rules.shot_kind(h.x, h.land_x), "shot %d tagged %s but lands as %s" % [h.shot, h.kind, Rules.shot_kind(h.x, h.land_x)])
			var my_y: float = h.y if h.side == "near" else BallModel.L - h.y
			_check(h.net == (my_y >= BallModel.NET_Y - Rules.NET_ZONE), "net zone tag wrong at y %.2f" % h.y)
			_check(h.strain >= 0.0 and h.strain <= 1.0, "a brain's hit has no strain")
			_check(h.you is Vector2 and h.shot_type == "", "shot %d: a brain's hit should carry your position and no shot type" % h.shot)
			if h.side == "near":
				near_hits += 1
				if h.net:
					near_net += 1
		if r.last_cause != "":
			causes += 1
		r.next_point()
	var k: Dictionary = r.tally
	_check(k.cross.hit + k.line.hit + k.mid.hit == near_hits, "the tally counts %d of near's %d shots" % [k.cross.hit + k.line.hit + k.mid.hit, near_hits])
	_check(k.net.hit == near_net, "the tally counts %d net shots, saw %d" % [k.net.hit, near_net])
	for kind in k:
		_check(k[kind].won <= k[kind].hit, "%s won more points than it was hit" % kind)
	near_won = k.cross.won + k.line.won + k.mid.won
	_check(near_won <= r.score.near, "won tallies (%d) beat near's score (%d)" % [near_won, r.score.near])
	var w: Dictionary = r.whiff_tally
	_check(w.easy + w.working + w.stretched <= far.whiffs, "more whiff causes than whiffs")
	_check(w.easy + w.working + w.stretched > 0, "no point in 40 ended on a whiff")
	_check(r.lobbed_at_net <= r.opp_lobs, "more lob points than lobs")
	_check(causes == 40, "only %d of 40 points have a cause" % causes)
	_match_free(n)
	return tagged


## two opponents play each other: every point ends, everyone stays on their half,
## rallies happen, the score adds up, and the same seeds play the same match
func _match_long_run() -> String:
	var a := _opp_vs_opp(150)
	var b := _opp_vs_opp(150)
	_check(a.score == b.score and a.lens == b.lens, "same seeds played two different matches: %s vs %s" % [a.score, b.score])
	_check(a.score.near + a.score.far == 150, "150 points should be scored, got %s" % a.score)
	_check(a.stuck == 0, "%d points never ended" % a.stuck)
	_check(a.outside == 0, "a body left its half %d times" % a.outside)
	var long := 0
	for l in a.lens:
		if l >= 3:
			long += 1
	_check(long >= 75, "only %d of 150 rallies had 3 or more hits" % long)
	var sorted: Array = a.lens.duplicate()
	sorted.sort()
	return "150 points, median rally %d, longest %d" % [sorted[75], sorted[-1]]


func _opp_vs_opp(points: int) -> Dictionary:
	var n := _match_nodes()
	var r = n[3]
	var near = Opponent.new(r, "near", 7)
	var far = Opponent.new(r, "far", 11)
	var lens := []
	var stuck := 0
	var outside := 0
	while r.points < points:
		var ticks := 0
		while r.state != "over" and ticks < 7200:   # 120 s, long rallies are fine
			near.tick(1.0 / 60.0)
			far.tick(1.0 / 60.0)
			r.tick(1.0 / 60.0)
			n[0]._physics_process(1.0 / 60.0)
			ticks += 1
			for body in [n[1], n[2]]:
				var lo: Vector2 = body.bounds_lo()
				var hi: Vector2 = body.bounds_hi()
				if body.px < lo.x - 1e-9 or body.px > hi.x + 1e-9 or body.py < lo.y - 1e-9 or body.py > hi.y + 1e-9:
					outside += 1
		if r.state != "over":
			stuck += 1
			r.state = "over"
			r.points += 1
		lens.append(r.rally_len)
		r.next_point()
	var out := {"score": r.score.duplicate(), "lens": lens, "stuck": stuck, "outside": outside}
	_match_free(n)
	return out
