extends SceneTree
## Headless profiler: godot --headless --path . -s res://tests/profile.gd
## Builds the real world and reports where simulation time goes.
func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var sim = main.sim
	sim.profile = true
	for i in 8:
		var us := Time.get_ticks_usec()
		sim.prewarm(60.0)
		print("PROFILE t=%d pop=%d animals=%d  %.2f ms/step  %s" % [sim.time, sim.population(), sim.eco.animals.size(), (Time.get_ticks_usec() - us) / 600000.0, sim.prof_report()])
		print("  eco ", sim.eco.counts(), " causes ", sim.eco.causes)
		sim.prof.clear()
	quit()
