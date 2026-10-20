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
##    opponent vs opponent plays long matches that always finish
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
	_check(JOY_BUTTON_A in Controls.ACTIONS.swing.buttons, "swing should be on the A button")
	# WASD drives movement
	for case in [[KEY_A, "move_left"], [KEY_D, "move_right"], [KEY_W, "move_up"], [KEY_S, "move_down"]]:
		_check(case[1] in _key_actions(case[0]), "%s should be bound to %s" % [OS.get_keycode_string(case[0]), case[1]])
	# lab keeps off the face buttons, they belong to the player
	for action in lab:
		for b in Controls.ACTIONS[action].get("buttons", []):
			_check(b > JOY_BUTTON_Y, "%s uses face button %d, keep those for the player" % [action, b])
	# stick: past the deadzone moves, inside it doesn't
	for case in [[JOY_AXIS_LEFT_X, -0.8, "move_left"], [JOY_AXIS_LEFT_X, 0.8, "move_right"], [JOY_AXIS_LEFT_Y, -0.8, "move_up"], [JOY_AXIS_LEFT_Y, 0.8, "move_down"]]:
		var e := InputEventJoypadMotion.new()
		e.axis = case[0]
		e.axis_value = case[1]
		e.device = 1
		_check(e.is_action_pressed(case[2]), "stick %s %.1f should press %s" % [case[0], case[1], case[2]])
		e.axis_value = case[1] * 0.1
		_check(not e.is_action_pressed(case[2]), "stick inside the deadzone pressed %s" % case[2])
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
	# reach and band
	p.reset(Vector2(5.0, 5.0))
	var mid := (PlayerNode.BAND_LOW + PlayerNode.BAND_HIGH) * 0.5
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
	var stats := _match_long_run()
	_summary("match: far half, lobs, shot choice, scoring, serves, opponent vs opponent", before,
		"(%d lobs, opponent returns %d%% of your drives, %s)" % [lobs, roundi(rate * 100.0), stats])


## a match with no brains: the test drives everything
func _match_nodes() -> Array:
	var ball = BallNode.new()
	var near = PlayerNode.new()
	var far = PlayerNode.new()
	return [ball, near, far, Rules.new(ball, near, far)]


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
		while r.state != "over" and ticks < 3600:
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
