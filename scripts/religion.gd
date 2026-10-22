class_name Religion
extends RefCounted
## Faith in the player-god. Every villager has `faith` (belief, 0-100) and
## `resentment` (grievance, 0-100). They change for concrete reasons:
##   + miracles witnessed (rain, plenty, life, forest, new land, gifts), worship,
##     priests' sermons, missionaries, divine protection during a crisis
##   - neglect (no miracle seen for a long time), famine, seeing kin smitten
##     by the god, persuasion by heretics
## A villager whose resentment outweighs their faith turns heretic (the cause
## is remembered). Heretics skip worship, refuse to build shrines and try to
## talk believers out of their faith; priests try to win them back. Heavy
## heresy creates tension (slower work, fewer births, heckled ceremonies) and
## can split a settlement (schism) into a heretic tribe.
## Worship produces prayer power, the resource the miracles cost.

const WORSHIP_MIN := 25.0
const BELIEVER := 30.0
const NEGLECT_AFTER := 150.0
const FOLK_FAITH := 18.0       # neglect alone never pushes belief below this
const PRAYER_CAP := 600.0

var sim
var prayer := 150.0
var sandbox := false
var stats := {"conversions": 0, "heresies": 0, "recants": 0, "ceremonies": 0, "missions": 0, "schisms": 0, "sermons": 0, "persuasions": 0}
var _t := 0.0
var _miracle_log_t := 0.0

func setup(p_sim) -> void:
	sim = p_sim

# ------------------------------------------------------------------ prayer
func can_afford(cost: float) -> bool:
	return sandbox or prayer >= cost

func spend(cost: float) -> bool:
	if sandbox: return true
	if prayer < cost: return false
	prayer -= cost
	return true

func add_prayer(a: float) -> void:
	prayer = minf(PRAYER_CAP, prayer + a)

# ------------------------------------------------------------------ queries
static func is_believer(v) -> bool:
	return not v.heretic and v.faith >= BELIEVER

func tribe_label(t) -> String:
	if t.heretical: return "Heretic"
	if t.devotion >= 70.0: return "Devout"
	if t.devotion >= 45.0: return "Faithful"
	if t.devotion >= 22.0: return "Wavering"
	return "Godless"

func totals() -> Dictionary:
	var w := 0
	var h := 0
	var p := 0
	var f := 0.0
	for v in sim.villagers:
		if v.heretic: h += 1
		elif v.faith >= BELIEVER: w += 1
		if v.priest: p += 1
		f += v.faith
	var shr := 0
	var tem := 0
	for t in sim.live_tribes():
		var s = t.shrine
		if s != null and s.alive and s.built:
			if s.type == "temple": tem += 1
			else: shr += 1
	return {"worshippers": w, "heretics": h, "priests": p, "avg_faith": f / maxf(1.0, sim.villagers.size()),
		"shrines": shr, "temples": tem}

# ------------------------------------------------------------------ events
## A divine act seen by everyone within radius.
## kind: "good" (miracle / blessing), "harm" (destruction) or "gift".
## victims: villagers hurt by the act (decides who grieves and who fears).
func witness(pos: Vector3, radius: float, kind: String, strength: float, victims: Array = []) -> int:
	var victim_tribes := {}
	var heretic_victims := 0
	for v in victims:
		victim_tribes[v.tribe] = true
		if v.heretic: heretic_victims += 1
	var punished_heretics: bool = victims.size() > 0 and heretic_victims * 2 >= victims.size()
	var n := 0
	var converted := 0
	for v in sim.villagers:
		if v.dead or v.is_busy_with_god(): continue
		if Vector2(v.position.x - pos.x, v.position.z - pos.z).length() > radius: continue
		n += 1
		v.last_miracle = sim.time
		if strength >= 5.0 and randf() < 0.6: v.react(kind, pos)
		match kind:
			"good", "gift":
				if v.heretic:
					var p := strength / 45.0 + (0.12 if v.tribe.has_temple() else 0.0)
					if randf() < p:
						_recant(v, "won back by a miracle")
						converted += 1
					else:
						v.resentment = maxf(0.0, v.resentment - strength * 0.8)
						v.faith = minf(100.0, v.faith + strength * 0.5)
				else:
					v.faith = minf(100.0, v.faith + strength * (1.0 - v.faith / 115.0))
					v.resentment = maxf(0.0, v.resentment - strength * 0.4)
			"harm":
				var kin: bool = victim_tribes.has(v.tribe) and not punished_heretics
				if v.heretic:
					if punished_heretics and v.resentment < 70.0 and randf() < 0.35:
						_recant(v, "cowed by divine punishment")
						converted += 1
					else:
						v.resentment = minf(100.0, v.resentment + strength * 0.8)
				elif punished_heretics:
					v.faith = minf(100.0, v.faith + strength * 0.35)   # justice seen to be done
				else:
					v.faith = minf(100.0, v.faith + strength * 0.2)    # awe and fear
					v.resentment = minf(100.0, v.resentment + strength * (1.0 if kin else 0.3))
					if kin: v.set_meta("grievance", "kin smitten by the god")
		v._update_marker()
	for t in sim.live_tribes():
		if t.center.distance_to(pos) < radius + 8.0:
			t.last_miracle = sim.time
	if kind != "harm" and n > 0 and sim.time - _miracle_log_t > 8.0:
		_miracle_log_t = sim.time
		sim.log_event("%d villagers witnessed a miracle%s." % [n, (" (%d heretics won back)" % converted) if converted > 0 else ""], Color(1.0, 0.9, 0.55))
	return n

## Famine, flood or fire without divine help breeds resentment.
func on_hardship(t, cause: String, amount: float) -> void:
	var helped: bool = sim.time - t.last_miracle < 60.0
	if t.has_shrine(): amount *= 0.6        # the faithful endure hardship better
	for v in t.members:
		if helped:
			v.faith = minf(100.0, v.faith + amount * 0.3)   # the god was there for us
		else:
			v.resentment = minf(100.0, v.resentment + amount)
			v.set_meta("grievance", cause)

func _recant(v, why: String) -> void:
	v.set_heretic(false)
	v.faith = maxf(v.faith, 42.0)
	v.resentment *= 0.35
	stats["recants"] += 1
	stats["conversions"] += 1
	if randf() < 0.5 or stats["recants"] < 4:
		sim.log_event("%s of %s returned to the faith (%s)." % [v.vname, v.tribe.name, why], Color(1.0, 0.85, 0.45))

func _turn(v, cause: String) -> void:
	v.set_heretic(true, cause)
	stats["heresies"] += 1
	sim.log_event("%s of %s has turned heretic (%s)." % [v.vname, v.tribe.name, cause], Color(0.75, 0.45, 0.95))

# ------------------------------------------------------------------ worship
func worship_spot(t, v) -> Vector3:
	var c: Vector3 = t.shrine_pos()
	var a := float(v.get_instance_id() % 97) / 97.0 * TAU
	var r := 2.4 + float(v.get_instance_id() % 7) * 0.35 + (1.4 if t.shrine.type == "temple" else 0.0)
	var p := c + Vector3(cos(a), 0, sin(a)) * r
	if not sim.nav.walkable(p): p = c + Vector3(cos(a), 0, sin(a)) * (r + 1.5)
	return p

func worship_tick(v, dt: float) -> void:
	var t = v.tribe
	var mult := 2.0 if t.has_temple() else 1.0
	if t.tension > 0.3: mult *= 0.5     # heretics heckle the ceremony
	add_prayer(dt * (0.12 + v.faith / 400.0) * mult)
	v.faith = minf(100.0, v.faith + dt * 0.45 * mult)
	v.resentment = maxf(0.0, v.resentment - dt * 0.3)

func priest_duty(v) -> bool:
	var t = v.tribe
	if t.mission_target != null and t.mission_target.alive and t.has_temple():
		v.mission_tribe = t.mission_target
		t.mission_target = null
		v.state = Villager.S.MISSION
		v.timer = 120.0
		stats["missions"] += 1
		sim.log_event("A priest of %s sets out to spread the faith to %s." % [t.name, v.mission_tribe.name], Color(1.0, 0.85, 0.45))
		return true
	var best = null
	var bd := 28.0
	for o in t.members:
		if o == v or o.dead or o.is_busy_with_god(): continue
		var d: float = o.position.distance_to(v.position)
		if o.heretic and d < bd:
			best = o
			bd = d
	if best == null and randf() < 0.35:
		for o in t.members:
			if o != v and not o.heretic and o.faith < 40.0 and not o.is_child() and o.position.distance_to(v.position) < 20.0:
				best = o
				break
	if best == null: return false
	v.other = best
	v.state = Villager.S.PREACH
	v.timer = 25.0
	return true

func heretic_duty(v) -> bool:
	for o in v.tribe.members:
		if o == v or o.dead or o.heretic or o.priest or o.is_child() or o.is_busy_with_god(): continue
		if o.faith < 75.0 and o.position.distance_to(v.position) < 22.0:
			v.other = o
			v.state = Villager.S.PREACH
			v.timer = 20.0
			return true
	return false

## a talks to b (a sermon if a is a believer/priest, persuasion if a is a heretic).
func preach(a, b) -> void:
	if a.heretic:
		if b.heretic or b.priest: return
		var resist := 0.5 if b.tribe.has_temple() else 1.0
		if sim.time - b.last_miracle < 60.0: resist *= 0.5
		resist *= clampf(1.1 - b.faith / 110.0, 0.15, 1.0)   # the devout are hard to sway
		b.faith = maxf(0.0, b.faith - 7.0 * resist)
		b.resentment = minf(100.0, b.resentment + 5.0 * resist)
		b.set_meta("grievance", "persuaded by heretics")
		stats["persuasions"] += 1
		b._update_marker()
		return
	stats["sermons"] += 1
	if b.heretic:
		var p: float = 0.22 + (0.3 if sim.time - b.last_miracle < 90.0 else 0.0) + (0.15 if a.tribe.has_temple() else 0.0) - b.resentment / 400.0
		if randf() < p:
			_recant(b, "persuaded by %s" % ("the priest" if a.priest else a.vname))
		else:
			b.resentment = maxf(0.0, b.resentment - 4.0)
	else:
		b.faith = minf(100.0, b.faith + (10.0 if a.priest else 5.0))
		b.resentment = maxf(0.0, b.resentment - 3.0)
		b._update_marker()

func mission_arrive(p, t) -> void:
	var n := 0
	for v in t.members:
		if v.position.distance_to(p.position) > 14.0: continue
		if v.heretic:
			if randf() < 0.25: _recant(v, "moved by a missionary")
		else:
			v.faith = minf(100.0, v.faith + 15.0)
		v._update_marker()
		n += 1
	t.last_miracle = sim.time
	sim.log_event("A missionary from %s preached to %d villagers of %s." % [p.tribe.name, n, t.name], Color(1.0, 0.85, 0.45))

# ------------------------------------------------------------------ simulation
func update(dt: float) -> void:
	_t -= dt
	if _t > 0.0: return
	_t = 1.0
	_tick(1.0)

func _tick(dt: float) -> void:
	var tribes: Array = sim.live_tribes()
	for t in tribes:
		_tick_tribe(t, dt)
	# devout towns influence their neighbours
	for a in tribes:
		if a.devotion < 60.0: continue
		for b in tribes:
			if b == a or b.heretical or b.center.distance_to(a.center) > 45.0: continue
			for v in b.members:
				if not v.heretic: v.faith = minf(100.0, v.faith + 0.04 * dt)

func _tick_tribe(t, dt: float) -> void:
	var pop: int = t.members.size()
	if pop == 0: return
	var has_shrine: bool = t.has_shrine()
	var has_temple: bool = t.has_temple()
	var heretics := 0
	var believers := 0
	var fsum := 0.0
	var priests: Array = []
	var neglect_mul := 0.25 if has_temple else (0.5 if has_shrine else 1.0)
	var starving: bool = t.food <= 0.5
	for v in t.members:
		if v.dead: continue
		var since: float = sim.time - v.last_miracle
		if since > NEGLECT_AFTER and not v.heretic and v.faith > FOLK_FAITH:
			v.faith = maxf(FOLK_FAITH, v.faith - 0.07 * neglect_mul * dt)
		elif since > NEGLECT_AFTER * 3.0 and not v.heretic and not has_shrine:
			v.resentment = minf(100.0, v.resentment + 0.03 * dt)
			if not v.has_meta("grievance"): v.set_meta("grievance", "the god's long silence")
		if not starving:
			v.resentment = maxf(0.0, v.resentment - (0.15 if has_shrine else 0.08) * dt)
		if t.heretical and v.heretic:
			v.faith = minf(v.faith, 35.0)
		# heresy onset / recovery: understandable thresholds, not random labels
		if not v.heretic and not v.priest and not v.is_child():
			if v.resentment > 35.0 and v.resentment > v.faith + 10.0:
				_turn(v, str(v.get_meta("grievance", "the god's long silence")))
		elif v.heretic and v.faith > v.resentment + 25.0:
			_recant(v, "faith restored")
		if v.heretic: heretics += 1
		elif v.faith >= BELIEVER: believers += 1
		if v.priest: priests.append(v)
		fsum += v.faith
		# believers' quiet prayers
		if not v.heretic and v.faith >= BELIEVER:
			add_prayer(dt * 0.006 * v.faith / 100.0 * (1.5 if has_shrine else 1.0))
		v._update_marker()
	t.worshippers = believers
	t.heretics = heretics
	t.devotion = fsum / pop
	t.tension = float(heretics) / pop
	if t.heretical and heretics == 0 and pop > 0:
		t.heretical = false
		sim.log_event("%s has returned to the faith!" % t.name, Color(1.0, 0.85, 0.45))
	# priests
	for p in priests:
		if not has_shrine: p.set_priest(false)
	var want_priests := (2 if has_temple else 1) if has_shrine else 0
	if priests.size() < want_priests:
		var best = null
		for v in t.members:
			if v.heretic or v.priest or v.is_child() or v.faith < 40.0: continue
			if best == null or v.faith > best.faith: best = v
		if best != null:
			best.set_priest(true)
			best.faith = maxf(best.faith, 70.0)
			sim.log_event("%s became a priest of %s." % [best.vname, t.name], Color(1.0, 0.92, 0.6))
	# ceremonies
	if has_shrine and (priests.size() > 0 or t.ceremony):
		if t.ceremony:
			t.ceremony_t -= dt
			if t.ceremony_t <= 0.0:
				t.ceremony = false
				t.inspired = 60.0
				t.next_ceremony = randf_range(45.0, 70.0) if has_temple else randf_range(70.0, 100.0)
		else:
			t.next_ceremony -= dt
			if t.next_ceremony <= 0.0 and believers >= 2:
				t.ceremony = true
				t.ceremony_t = 16.0
				stats["ceremonies"] += 1
				if stats["ceremonies"] <= 3 or randf() < 0.25:
					sim.log_event("%s gathers to worship at the %s." % [t.name, t.shrine.type], Color(1.0, 0.92, 0.6))
	else:
		t.ceremony = false
	t.inspired = maxf(0.0, t.inspired - dt)
	# missionaries
	if has_temple:
		t.mission_t -= dt
		if t.mission_t <= 0.0:
			t.mission_t = randf_range(90.0, 140.0)
			var best = null
			var bd := 80.0
			for o in sim.live_tribes():
				if o == t or o.devotion > t.devotion - 10.0: continue
				var d: float = o.center.distance_to(t.center)
				if d < bd and sim.nav.connected(t.center, o.center):
					bd = d
					best = o
			t.mission_target = best
	# schism: a heretic majority faction leaves
	if heretics >= 4 and t.tension >= 0.45 and not t.heretical:
		_schism(t)
	# lone heretics leave very devout towns for a heretic one
	elif heretics > 0 and t.devotion > 55.0 and randf() < 0.02 * dt:
		for v in t.members:
			if v.heretic and v.resentment > 70.0:
				var dest = _nearest_tribe(t, true, v)
				if dest != null:
					sim.migrate(v, dest)
					sim.log_event("%s left %s to live among the heretics of %s." % [v.vname, t.name, dest.name], Color(0.75, 0.45, 0.95))
				break

func _nearest_tribe(from, heretical: bool, v) -> Variant:
	var best = null
	var bd := 100.0
	for o in sim.live_tribes():
		if o == from or o.heretical != heretical: continue
		var d: float = o.center.distance_to(from.center)
		if d < bd and v.can_reach(o.center):
			bd = d
			best = o
	return best

func _schism(t) -> void:
	if sim.live_tribes().size() >= sim.MAX_TRIBES: return
	var spot = sim.find_settle_spot(28.0, t.center, 60.0)
	if spot == null or not sim.nav.connected(t.center, spot): return
	var nt = sim.create_tribe(spot)
	nt.heretical = true
	nt.wood = 10.0
	nt.food = 10.0
	var movers: Array = t.members.filter(func(v): return v.heretic)
	for v in movers:
		sim.migrate(v, nt)
	stats["schisms"] += 1
	sim.log_event("Schism! %d heretics broke away from %s and founded %s." % [movers.size(), t.name, nt.name], Color(0.8, 0.45, 1.0))
