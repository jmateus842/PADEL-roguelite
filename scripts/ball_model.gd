extends RefCounted
## The ball, as pure data and rules. Port of simulate() in sim/wall_shots.py.
## Position on the court (x, y) plus a fake height z. No physics engine.
## Always steps at DT, whatever the frame rate, so it matches the sim's plots.
## Plain floats on purpose: Vector3 is 32-bit in Godot, GDScript floats are 64-bit like Python.

# court in meters. x goes across (0..10), y goes along (0..20)
# we play on the near half (y < 10), the opponent on the far half
const W := 10.0
const L := 20.0
const NET_Y := 10.0
const NET_H := 0.88
const SERVICE_FROM_NET := 6.95

# --- tuning: same numbers as the sim ---
const G := 9.81
const DRAG := 0.02
const FLOOR_E := 0.74
const FLOOR_GRIP := 0.85
const GLASS_E := 0.65
const MESH_E := 0.25
const WALL_GRIP := 0.9
const REACH_LOW := 0.3
const REACH_HIGH := 1.9
const DT := 0.002
const MAX_T := 5.0

var x := 0.0
var y := 0.0
var z := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var t := 0.0
var kick := 1.0

## every step as t, x, y, z one after the other
var path := PackedFloat64Array()
var events: Array[Dictionary] = []
## empty while the point is alive
var end := ""

var _floor_near := 0
var _floor_far := 0
var _crossed := false


static func wall_at(side: String, along: float) -> Vector2:
	## (glass height, total height) of a wall at a given point.
	## back walls: 3m glass + 1m mesh. side walls step down toward the net.
	## the 2m/2m split on the side is the common build, not a rule
	if side == "back":
		return Vector2(3.0, 4.0)
	var d: float = min(along, L - along)
	if d < 2.0:
		return Vector2(3.0, 4.0)
	if d < 4.0:
		return Vector2(2.0, 3.0)
	return Vector2(0.0, 3.0)


static func half(at_y: float) -> String:
	return "near" if at_y < NET_Y else "far"


static func launch(start: Array, speed: float, elevation_deg: float, target: Array) -> Array:
	## velocity toward a target point on the court, with an up/down angle
	var dx: float = target[0] - start[0]
	var dy: float = target[1] - start[1]
	var flat := sqrt(dx * dx + dy * dy)
	var el := deg_to_rad(elevation_deg)
	return [speed * cos(el) * dx / flat, speed * cos(el) * dy / flat, speed * sin(el)]


func reset(start: Array, vel: Array, kick_amount := 1.0) -> void:
	x = start[0]
	y = start[1]
	z = start[2]
	vx = vel[0]
	vy = vel[1]
	vz = vel[2]
	kick = kick_amount
	t = 0.0
	end = ""
	events.clear()
	path = PackedFloat64Array([t, x, y, z])
	_floor_near = 0
	_floor_far = 0
	_crossed = false


## true once the ball has crossed the net toward the far side.
## The receiver may only play it after that.
func crossed() -> bool:
	return _crossed


func is_done() -> bool:
	return end != ""


func run_to_end() -> void:
	while not is_done():
		step()


func step() -> void:
	if is_done():
		return
	if t >= MAX_T:
		end = "timeout"
		return

	var speed := sqrt(vx * vx + vy * vy + vz * vz)
	vx -= DRAG * speed * vx * DT
	vy -= DRAG * speed * vy * DT
	vz -= (G + DRAG * speed * vz) * DT
	var prev_y := y
	var prev_z := z
	x += vx * DT
	y += vy * DT
	z += vz * DT
	t += DT

	# net: interpolate the height where it crosses y = 10
	if (prev_y - NET_Y) * (y - NET_Y) < 0.0:
		var k := (NET_Y - prev_y) / (y - prev_y)
		var z_at_net := prev_z + k * (z - prev_z)
		var coming_back := _crossed and vy < 0.0
		if z_at_net < NET_H and not coming_back:
			_log("net")
			end = "net"
			return
		if z_at_net < NET_H:
			# bounced off their glass and ran into the net from behind
			y = 2.0 * NET_Y - y
			vy = -vy * 0.2
			vx *= 0.5
			_log("net", "from behind")
		elif coming_back:
			_log("crosses net", "back to us")
			end = "winner: came back over the net"
			return
		else:
			_crossed = true
			_log("crosses net", "%.2fm over" % (z_at_net - NET_H))

	if z <= 0.0:
		# no spin in this model, kick fakes it on the first bounce only
		var e := FLOOR_E * (kick if _floor_near + _floor_far == 0 else 1.0)
		z = -z * e
		vz = -vz * e
		vx *= FLOOR_GRIP
		vy *= FLOOR_GRIP
		var h := half(y)
		if h == "near":
			_floor_near += 1
		else:
			_floor_far += 1
		_log("floor", h)
		if h == "near" and not _crossed:
			end = "fault: bounced on our side"
		elif h == "far" and _floor_far == 2:
			end = "winner: second bounce"
		elif vz < 0.4:
			end = "ball died"

	# walls. each one: is the ball under the top? glass or mesh?
	for wall in [["x", 0.0, "side"], ["x", W, "side"], ["y", 0.0, "back"], ["y", L, "back"]]:
		var axis: String = wall[0]
		var limit: float = wall[1]
		var side: String = wall[2]
		var pos := x if axis == "x" else y
		var past := pos < limit if limit == 0.0 else pos > limit
		if not past or is_done():
			continue
		var along := y if axis == "x" else x
		var heights := wall_at(side, along)
		var glass_h := heights.x
		var top := heights.y
		var h := half(y)
		if z > top:
			_log("over the wall", side)
			if h == "far" and _floor_far == 1:
				end = "winner: out over the %s wall" % side
			else:
				end = "out"
			break
		var material := "glass" if z <= glass_h else "mesh"
		# rule check before bouncing it
		if h == "far" and _floor_far == 0:
			_log(material, side)
			end = "out: hit their %s %s before bouncing" % [side, material]
			break
		if h == "near" and not _crossed and material == "mesh":
			_log(material, side)
			end = "fault: hit our own mesh"
			break
		var e := GLASS_E if material == "glass" else MESH_E
		if axis == "x":
			x = 2.0 * limit - x
			vx = -vx * e
			vy *= WALL_GRIP
		else:
			y = 2.0 * limit - y
			vy = -vy * e
			vx *= WALL_GRIP
		vz *= WALL_GRIP
		_log(material, side)

	path.append_array([t, x, y, z])


func _log(kind: String, detail := "") -> void:
	events.append({"t": t, "kind": kind, "x": x, "y": y, "z": z, "detail": detail})


func playable_windows() -> Array:
	## stretches where the opponent can hit it: after the first bounce on their
	## side, before the second, at a comfortable height, inside the court.
	## each window is [t_start, t_end]
	var first := -1.0
	for e in events:
		if e.kind == "floor" and e.detail == "far":
			first = e.t
			break
	if first < 0.0:
		return []
	var windows := []
	var current := []
	for i in range(0, path.size(), 4):
		var pt := path[i]
		var px := path[i + 1]
		var py := path[i + 2]
		var pz := path[i + 3]
		var ok := pt > first and 0.0 < px and px < W and NET_Y < py and py < L \
			and REACH_LOW <= pz and pz <= REACH_HIGH
		if ok and current.is_empty():
			current = [pt, pt]
		elif ok:
			current[1] = pt
		elif not current.is_empty():
			windows.append(current)
			current = []
	if not current.is_empty():
		windows.append(current)
	# tiny slivers are just the ball passing through the band
	return windows.filter(func(w): return w[1] - w[0] > 0.05)


func hittable_time() -> float:
	var total := 0.0
	for w in playable_windows():
		total += w[1] - w[0]
	return total


func describe() -> String:
	## same story string as the sim's summary.md
	var parts: PackedStringArray = []
	for e in events:
		match e.kind:
			"crosses net":
				if e.detail == "back to us":
					parts.append("back over the net")
				else:
					parts.append("net +%sm" % e.detail.split("m")[0])
			"floor":
				parts.append("floor(%.1f)" % e.y)
			"glass", "mesh":
				parts.append("%s %s(z %.1f)" % [e.detail, e.kind, e.z])
			"over the wall":
				parts.append("over the %s wall" % e.detail)
			"net":
				parts.append("net from behind" if e.detail != "" else "net")
	return " > ".join(parts)


func summary_row(shot_name: String) -> String:
	return "| %s | %s | %.2fs | %d | %s |" % [shot_name, end, hittable_time(), playable_windows().size(), describe()]
