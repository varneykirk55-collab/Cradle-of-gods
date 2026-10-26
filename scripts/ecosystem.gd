class_name Ecosystem
extends Node3D
## Wildlife: deer (grazers that also browse berry bushes), rabbits (fast
## breeders), wolves (pack predators) and birds (fly, perch near trees).
## Populations are limited by local crowding and food, so predators, hunters
## and divine powers visibly shift the balance.

const SPEC := {
	"deer": {"name": "Deer", "scale": 1.0, "walk": 1.3, "run": 4.6, "alert": 6.0, "life": 420.0, "hunger": 0.0045,
		"graze": 0.05, "breed": 55.0, "grow": 60.0, "cap": 70, "local": 9, "meat": 7.0, "vis": 150.0, "gait": 2.4,
		"biomes": [Terrain.Biome.GRASS, Terrain.Biome.FOREST, Terrain.Biome.DRY, Terrain.Biome.ALPINE]},
	"rabbit": {"name": "Rabbit", "scale": 1.25, "walk": 1.4, "run": 3.9, "alert": 5.0, "life": 220.0, "hunger": 0.008,
		"graze": 0.06, "breed": 40.0, "grow": 30.0, "cap": 90, "local": 12, "meat": 2.5, "vis": 90.0, "gait": 3.0,
		"biomes": [Terrain.Biome.GRASS, Terrain.Biome.DRY, Terrain.Biome.BEACH, Terrain.Biome.FOREST]},
	"wolf": {"name": "Wolf", "scale": 1.05, "walk": 1.6, "run": 5.0, "alert": 0.0, "life": 380.0, "hunger": 0.0075,
		"graze": 0.0, "breed": 110.0, "grow": 70.0, "cap": 16, "local": 5, "meat": 0.0, "vis": 150.0, "gait": 2.6,
		"biomes": [Terrain.Biome.FOREST, Terrain.Biome.ALPINE, Terrain.Biome.GRASS]},
	"bird": {"name": "Bird", "scale": 2.2, "walk": 0.0, "run": 5.5, "alert": 5.0, "life": 300.0, "hunger": 0.004,
		"graze": 0.04, "breed": 80.0, "grow": 30.0, "cap": 40, "local": 10, "meat": 0.0, "vis": 160.0, "gait": 1.6,
		"biomes": [Terrain.Biome.GRASS, Terrain.Biome.FOREST, Terrain.Biome.BEACH, Terrain.Biome.DRY]},
}
const START := {"deer": 26, "rabbit": 32, "wolf": 7, "bird": 18}

var sim
var animals: Array = []
var causes := {}
var grid := {}

func rebuild_grid() -> void:
	grid.clear()
	for a in animals:
		var k := WorldSim.gkey(a.position)
		if grid.has(k): grid[k].append(a)
		else: grid[k] = [a]

func near(p: Vector3, r: float) -> Array:
	return WorldSim.grid_near(grid, p, r)
var stats := {"born": 0, "died": 0, "predation": 0, "hunted": 0, "starved": 0}

func setup(p_sim) -> void:
	sim = p_sim
	for sp in START:
		var packs: int = 3 if sp == "wolf" else START[sp] / 3
		var made := 0
		for i in packs * 4:
			if made >= START[sp]: break
			var c = _random_habitat(sp)
			if c == null: continue
			if sp != "bird" and _near_tribe(c, 14.0): continue
			for j in (3 if sp != "wolf" else 2) + (1 if sp == "wolf" and i % 2 == 0 else 0):
				if made >= START[sp]: break
				var p: Vector3 = c + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
				if sim.terrain.is_land(p.x, p.z):
					spawn(sp, p, false)
					made += 1

func count(sp: String) -> int:
	var n := 0
	for a in animals:
		if a.species == sp: n += 1
	return n

func counts() -> Dictionary:
	var d := {"deer": 0, "rabbit": 0, "wolf": 0, "bird": 0}
	for a in animals:
		d[a.species] += 1
	return d

func spawn(sp: String, pos: Vector3, baby: bool) -> Animal:
	if count(sp) >= SPEC[sp]["cap"] * (1.3 if not baby else 1.0): return null
	var a := Animal.new()
	add_child(a)
	pos.y = sim.terrain.height_at(pos.x, pos.z)
	a.setup(self, sp, pos, baby)
	if sp == "bird":
		a._bird_target()
	else:
		a._wander()
	animals.append(a)
	return a

func kill(a, cause: String) -> void:
	if a == null or a.dead: return
	a.dead = true
	animals.erase(a)
	stats["died"] += 1
	if cause == "starvation": stats["starved"] += 1
	var k := "%s_%s" % [a.species, cause]
	causes[k] = causes.get(k, 0) + 1
	FX.soul(sim, a.position)
	var tw := create_tween()
	tw.tween_property(a, "scale", Vector3(1.2, 0.05, 1.2) * a.grow, 0.35)
	tw.tween_callback(a.queue_free)

func kill_in_radius(pos: Vector3, r: float, cause: String) -> int:
	var n := 0
	for a in animals.duplicate():
		if a.is_busy_with_god(): continue
		if Vector2(a.position.x - pos.x, a.position.z - pos.z).length() <= r and (a.species != "bird" or a.state == Animal.S.PERCH or a.position.y - sim.terrain.height_at(pos.x, pos.z) < 6.0):
			kill(a, cause)
			n += 1
	return n

var _n := 0

func update(dt: float) -> void:
	_n += 1
	var cam: Camera3D = sim.cam
	for a in animals.duplicate():
		if a.dead: continue
		if a.is_busy_with_god() or cam == null or (a.position.distance_squared_to(sim.cam_pos) < 14400.0 and cam.is_position_in_frustum(a.position)):
			a.tick(dt)
		elif (a.get_instance_id() + _n) % 2 == 0:
			a.tick(dt * 2.0)   # off-screen animals think at half rate

# ------------------------------------------------------------------ queries
func _near_tribe(p: Vector3, r: float) -> bool:
	for t in sim.tribes:
		if t.alive and Vector2(t.center.x - p.x, t.center.z - p.z).length() < r: return true
	return false

func _random_habitat(sp: String) -> Variant:
	var b: Array = SPEC[sp]["biomes"]
	for i in 60:
		var p := Vector3(randf_range(-Terrain.HALF + 8, Terrain.HALF - 8), 0, randf_range(-Terrain.HALF + 8, Terrain.HALF - 8))
		if sim.terrain.biome_at(p.x, p.z) in b:
			p.y = sim.terrain.height_at(p.x, p.z)
			return p
	return null

## Herd / pack cohesion: wander targets drift toward nearby kin.
func kin_center(a, r: float) -> Variant:
	var c := Vector3.ZERO
	var n := 0
	for o in near(a.position, r):
		if o != a and o.species == a.species and not o.dead:
			c += o.position
			n += 1
	return c / n if n > 0 else null

func habitat_target(a) -> Vector3:
	var b: Array = a.spec["biomes"]
	var kin = kin_center(a, 24.0)
	if kin != null and a.position.distance_to(kin) > 6.0 and randf() < 0.6:
		var toward: Vector3 = kin + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		if sim.terrain.is_land(toward.x, toward.z): return toward
	var best: Vector3 = a.position
	for i in 10:
		var ang := randf() * TAU
		var p: Vector3 = a.position + Vector3(cos(ang), 0, sin(ang)) * randf_range(4.0, 14.0)
		if not sim.terrain.in_bounds(p.x, p.z, 4.0) or not sim.terrain.is_land(p.x, p.z): continue
		if a.species != "wolf" and _near_tribe(p, 9.0): continue
		if a.species == "wolf" and a.hunger < 0.8 and _near_tribe(p, 16.0): continue
		best = p
		if sim.terrain.biome_at(p.x, p.z) in b: return p
	return best

## Nearest predator, nearby person or fire the animal should run from.
func threat_for(a, r: float) -> Variant:
	if r <= 0.0: return null
	var p: Vector3 = a.position
	if a.species != "wolf":
		for o in near(p, r * 1.3):
			if o.species == "wolf" and not o.dead and not o.is_busy_with_god():
				if Vector2(o.position.x - p.x, o.position.z - p.z).length() < r * 1.3:
					return o.position
	for v in WorldSim.grid_near(sim.vgrid, p, r * 1.4):
		if v.is_busy_with_god(): continue
		var d := Vector2(v.position.x - p.x, v.position.z - p.z).length()
		if d < (r * 1.4 if v.state == Villager.S.HUNT else r * 0.55):
			return v.position
	for f in sim.fires:
		var fp: Vector3 = f["res"].pos if f["res"] != null else f["bld"].pos
		if absf(fp.x - p.x) < 9.0 and absf(fp.z - p.z) < 9.0:
			return fp
	return null

func find_wolf_prey(w, r: float) -> Variant:
	var best = null
	var bd := r
	for o in near(w.position, r):
		if o.dead or o.is_busy_with_god() or not (o.species in ["deer", "rabbit"]): continue
		var d: float = o.position.distance_to(w.position)
		if o.species == "deer" and o.is_adult(): d *= 1.2   # wolves prefer easier prey
		if d < bd:
			bd = d
			best = o
	if best == null and w.hunger > 0.85:
		for v in WorldSim.grid_near(sim.vgrid, w.position, 16.0):   # a starving wolf will go for a lone villager
			if v.is_busy_with_god(): continue
			var d: float = v.position.distance_to(w.position)
			if d < 16.0 and d < bd:
				bd = d
				best = v
	return best

func predation(w, prey) -> void:
	w.hunger = 0.0
	stats["predation"] += 1
	if prey is Villager:
		sim.kill_villager(prey, "wolves")
		sim.log_event("Wolves killed %s of %s!" % [prey.vname, prey.tribe.name], Color(0.85, 0.5, 0.4))
		sim.religion.on_hardship(prey.tribe, "wolves took our people", 4.0)
	else:
		kill(prey, "wolves")

## Sustainable hunting: villagers only hunt where a species is plentiful
## (breeding stock is left alone) and only a few hunters per settlement.
func find_prey(pos: Vector3, r: float, hunter) -> Variant:
	var t = hunter.tribe
	var hunters := 0
	for v in t.members:
		if v.state == Villager.S.HUNT: hunters += 1
	if hunters >= maxi(1, t.members.size() / 8): return null
	var local := {"deer": 0, "rabbit": 0}
	var cands := near(pos, r)
	for o in cands:
		if local.has(o.species): local[o.species] += 1
	var best = null
	var bd := r
	for o in cands:
		if o.dead or o.is_busy_with_god() or not local.has(o.species): continue
		if local[o.species] < 4 or count(o.species) < SPEC[o.species]["cap"] * 0.25: continue
		var d: float = o.position.distance_to(pos)
		if d < bd and hunter.can_reach(o.position):
			bd = d
			best = o
	return best

## A villager's spear throw; returns meat on success.
func try_hunt(v, a) -> float:
	if a.dead: return 0.0
	var chance := 0.45 if a.species == "deer" else 0.65
	if a.state == Animal.S.GRAZE or a.state == Animal.S.REST: chance += 0.2
	if randf() < chance:
		var meat: float = a.spec["meat"] * a.grow
		kill(a, "hunted")
		stats["hunted"] += 1
		return meat
	a.threat = v.position
	a.state = Animal.S.FLEE
	a.timer = 3.0
	return 0.0

## Deer browse berry bushes, competing with villagers for food.
func browse_bush(a) -> void:
	var b = sim.find_nearest(a.position, WorldSim.RES_BUSH, 3.0)
	if b != null:
		sim.harvest(b, 1.0)
		a.hunger = maxf(0.0, a.hunger - 0.25)

func perch_spot(bird) -> Variant:
	var t = sim.find_nearest(bird.position, WorldSim.RES_TREE, 25.0)
	if t != null:
		return t.pos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	return null

func try_breed(a) -> void:
	var sp: String = a.species
	if count(sp) >= SPEC[sp]["cap"]: return
	var crowd := 0
	var mate := false
	var mate_r := 30.0 if sp == "bird" else 14.0
	for o in near(a.position, 25.0):
		if o.species != sp or o == a: continue
		var d: float = o.position.distance_to(a.position)
		if d < 25.0:
			crowd += 1
			if d < mate_r and o.is_adult(): mate = true
	if not mate or crowd >= SPEC[sp]["local"]: return
	if sp != "wolf" and sp != "bird" and sim.terrain.fertility_at(a.position.x, a.position.z) < -0.4: return
	var babies := 2 if sp == "rabbit" else 1
	for i in babies:
		var bp: Vector3 = a.position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		if sp != "bird" and not sim.terrain.is_land(bp.x, bp.z): bp = a.position
		var b := spawn(sp, bp, true)
		if b != null:
			stats["born"] += 1
			if sp == "bird":
				b.position.y = a.position.y

func on_landed(a, v: Vector3) -> void:
	var sp := v.length()
	sim.impact.emit(a.position, sp, "animal")
	if sp > 14.0 or (a.species != "bird" and sim.terrain.height_at(a.position.x, a.position.z) < Terrain.SEA - 0.5):
		kill(a, "thrown")
		sim.religion.witness(a.position, 18.0, "harm", 3.0)
	elif sp > 7.0:
		a.state = Animal.S.STUNNED
		a.timer = 2.5
		FX.dust(sim, a.position)
	else:
		a._wander()
