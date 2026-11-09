class_name SaveGame
extends RefCounted
## One-slot save / load in Godot's user:// folder.
##
## The save holds the actual world, not just its seed: the full heightmap with
## every edit, moisture and fertility, all trees / rocks / bushes, every tribe
## with its buildings and stores, every villager (faith, role, age, carried
## goods, tiredness), every animal, fires, prayer, the infinite-prayer toggle,
## counters and the camera. Loading replaces the current world completely, so
## nothing is ever duplicated.
##
## Files are written with FileAccess.store_var (binary, no objects) to a
## temporary file first and then moved into place, keeping the previous save as
## a .bak. A missing, damaged or incompatible save is reported and the current
## world is left untouched: everything is validated before anything is removed.

const VERSION := 1
const MAGIC := "CRADLE_OF_GODS_SAVE"
const DEFAULT_PATH := "user://savegame.dat"

## Why the world can't be saved (or loaded) right now, or "" when it can.
## Things in the God Hand or in mid-air have no stable place to be saved.
static func busy_reason(main) -> String:
	if main.hand != null and main.hand.held != null:
		return "Put down what the God Hand is holding first."
	if not main.sim.props.is_empty():
		return "Wait for thrown things to land first."
	for v in main.sim.villagers:
		if v.state == Villager.S.FLYING or v.state == Villager.S.CARRIED:
			return "Wait for thrown villagers to land first."
	for a in main.sim.eco.animals:
		if a.state == Animal.S.FLYING or a.state == Animal.S.CARRIED:
			return "Wait for thrown animals to land first."
	return ""

static func _summary(main) -> String:
	var sim: WorldSim = main.sim
	return "Year %d, %d people in %d settlements, %d buildings" % [
		int(sim.time / 60.0) + 1, sim.population(), sim.live_tribes().size(), sim.building_count()]

## Save the current world to path. Returns {"ok": bool, "msg": String}.
static func save(main, path := DEFAULT_PATH) -> Dictionary:
	var why := busy_reason(main)
	if why != "": return {"ok": false, "msg": "Can't save yet: " + why}
	var rel: Religion = main.sim.religion
	var data := {
		"magic": MAGIC,
		"version": VERSION,
		"engine": Engine.get_version_info().get("string", ""),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"summary": _summary(main),
		"world_seed": main.world_seed,
		"terrain": main.terrain.save_state(),
		"sim": main.sim.serialize(),
		"religion": {"prayer": rel.prayer, "sandbox": rel.sandbox, "stats": rel.stats.duplicate(),
			"miracle_log_t": rel._miracle_log_t},
		"powers": {"brush": main.powers.brush, "land_mode": main.powers.land_mode, "life_type": main.powers.life_type},
		"camera": {"focus": main.rig.focus, "dist": main.rig.dist, "yaw": main.rig.yaw, "pitch": main.rig.pitch},
	}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "msg": "Could not write the save file (error %d)." % FileAccess.get_open_error()}
	f.store_var(data, false)
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "msg": "Could not write the save file (error %d)." % err}
	# swap into place, keeping the previous save as a backup
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return {"ok": false, "msg": "Could not finish writing the save file (error %d)." % err}
	return {"ok": true, "msg": "World saved (%s)." % data["summary"]}

## Read and validate a save without touching the world.
## Returns {"ok", "msg", "data"}.
static func read(path := DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "msg": "No saved world found.", "data": null}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "msg": "The save file could not be opened (error %d)." % FileAccess.get_open_error(), "data": null}
	var data = null
	if f.get_length() > 0:
		data = f.get_var(false)
	f.close()
	if not (data is Dictionary) or data.get("magic", "") != MAGIC:
		return {"ok": false, "msg": "The save file is damaged or not a Cradle of Gods save. Your current world was kept.", "data": null}
	if int(data.get("version", -1)) != VERSION:
		return {"ok": false, "msg": "The save was made by an incompatible version of the game (save format %s, this game reads %d). Your current world was kept." % [str(data.get("version", "?")), VERSION], "data": null}
	if not Terrain.valid_state(data.get("terrain")) or not WorldSim.valid_state(data.get("sim")) \
			or not (data.get("religion") is Dictionary):
		return {"ok": false, "msg": "The save file is incomplete or damaged. Your current world was kept.", "data": null}
	return {"ok": true, "msg": "", "data": data}

## What the slot holds, for the UI. {"ok", "msg", "when", "summary"}
static func peek(path := DEFAULT_PATH) -> Dictionary:
	var r := read(path)
	if not r["ok"]: return {"ok": false, "msg": r["msg"], "when": "", "summary": ""}
	var d: Dictionary = r["data"]
	return {"ok": true, "msg": "", "when": str(d.get("saved_at", "")), "summary": str(d.get("summary", ""))}

## Replace the current world with the one saved at path.
## Returns {"ok": bool, "msg": String}.
static func load_into(main, path := DEFAULT_PATH) -> Dictionary:
	var why := busy_reason(main)
	if why != "": return {"ok": false, "msg": "Can't load yet: " + why}
	var r := read(path)
	if not r["ok"]: return {"ok": false, "msg": r["msg"]}
	var d: Dictionary = r["data"]
	var hand: GodHand = main.hand
	if hand != null:
		hand.hover = null
		hand.state = GodHand.H.IDLE
		hand.hover_changed.emit("")
	main.world_seed = int(d.get("world_seed", main.world_seed))
	main.terrain.load_state(d["terrain"])
	main.sim.restore(d["sim"])
	var rel: Religion = main.sim.religion
	var rd: Dictionary = d["religion"]
	rel.prayer = clampf(float(rd.get("prayer", rel.prayer)), 0.0, Religion.PRAYER_CAP)
	rel.sandbox = bool(rd.get("sandbox", rel.sandbox))
	var st = rd.get("stats", {})
	if st is Dictionary:
		for k in st: rel.stats[k] = st[k]
	rel._miracle_log_t = float(rd.get("miracle_log_t", 0.0))
	rel.reset_income()
	var pd = d.get("powers", {})
	if pd is Dictionary:
		main.powers.brush = clampf(float(pd.get("brush", main.powers.brush)), Powers.BRUSH_MIN, Powers.BRUSH_MAX)
		if str(pd.get("land_mode", "")) in ["brush", "tile"]: main.powers.land_mode = str(pd["land_mode"])
		if str(pd.get("life_type", "")) in Powers.LIFE_TYPES: main.powers.life_type = str(pd["life_type"])
	if main.powers.current >= 0: main.powers.select(main.powers.current)   # back to the hand
	var cd = d.get("camera", {})
	if cd is Dictionary and cd.get("focus") is Vector3:
		main.rig.set_view(cd["focus"], float(cd.get("dist", 55.0)), float(cd.get("yaw", 0.7)), float(cd.get("pitch", 0.8)), true)
	if main.hud != null: main.hud.after_load()
	return {"ok": true, "msg": "World loaded (%s)." % str(d.get("summary", ""))}
