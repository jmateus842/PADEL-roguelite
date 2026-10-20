extends SceneTree
## Headless check: runs every shot through the Godot ball model and compares
## it with sim/shots/summary.md. Exit code 1 if anything differs.
##   godot --headless --path . --script res://scripts/check_shots.gd

const Shots := preload("res://scripts/shots.gd")


func _init() -> void:
	var results := Shots.run_all()
	var bad := 0
	for shot_name in results:
		var r: Dictionary = results[shot_name]
		var tag := "  ?? " if r.match == null else ("  ok " if r.match else "DIFF ")
		if r.match != true:
			bad += 1
		print(tag, r.row)
	print("\n%d/%d shots match the sim" % [results.size() - bad, results.size()])
	quit(1 if bad else 0)
