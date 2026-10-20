extends RefCounted
## Same launch values as SHOTS in sim/wall_shots.py. Change both together.
## start [x, y, z], speed m/s, elevation deg, aim point [x, y], kick

const SHOTS := {
	"drive_to_back_glass": [[5.0, 7.0, 1.0], 17.0, 8.0, [5.0, 20.0], 1.0],
	"lob": [[5.0, 3.0, 1.0], 13.0, 45.0, [5.0, 20.0], 1.0],
	"cross_to_side_glass": [[2.0, 8.0, 1.0], 17.0, 8.0, [10.0, 17.0], 1.0],
	"double_wall": [[3.0, 7.0, 1.0], 17.0, 8.0, [10.0, 19.5], 1.0],
	"smash_flat": [[5.0, 8.5, 2.7], 30.0, -25.0, [5.0, 20.0], 1.0],
	"smash_por_3": [[5.0, 8.5, 2.7], 30.0, -40.0, [5.0, 20.0], 1.0],
	"smash_por_4_kick": [[7.0, 8.5, 2.7], 30.0, -40.0, [10.0, 13.5], 1.6],
	"corner_kill": [[5.0, 8.0, 2.2], 14.0, -8.0, [9.6, 19.0], 1.0],
	"into_the_mesh": [[5.0, 8.0, 1.0], 11.0, 10.0, [10.0, 13.5], 1.0],
	"contrapared": [[5.0, 1.5, 0.9], 22.0, 32.0, [5.0, 0.0], 1.0],
	"too_long": [[5.0, 7.0, 1.0], 27.0, 6.0, [5.0, 20.0], 1.0],
}

const BallModel := preload("res://scripts/ball_model.gd")


static func names() -> Array:
	return SHOTS.keys()


static func load_into(model, shot_name: String) -> void:
	var s: Array = SHOTS[shot_name]
	model.reset(s[0], BallModel.launch(s[0], s[1], s[2], s[3]), s[4])


static func expected_rows() -> Dictionary:
	## rows from sim/shots/summary.md, keyed by shot name. empty if the file is missing
	var rows := {}
	var f := FileAccess.open("res://sim/shots/summary.md", FileAccess.READ)
	if f == null:
		return rows
	for line in f.get_as_text().split("\n"):
		var cells := line.split("|")
		if cells.size() > 2 and SHOTS.has(cells[1].strip_edges()):
			rows[cells[1].strip_edges()] = line.strip_edges()
	return rows


static func run_all() -> Dictionary:
	## runs every shot to the end. returns {name: {"row": ..., "match": bool or null}}
	var expected := expected_rows()
	var out := {}
	for shot_name in names():
		var m = BallModel.new()
		load_into(m, shot_name)
		m.run_to_end()
		var row: String = m.summary_row(shot_name)
		out[shot_name] = {"row": row, "match": (row == expected[shot_name]) if expected.has(shot_name) else null}
	return out
