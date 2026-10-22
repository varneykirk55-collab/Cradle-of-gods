class_name FX
extends RefCounted
## Particle / visual-effect factory (CPUParticles3D so it runs on the
## Compatibility renderer and on machines without a GPU).

static var _mats := {}

static func pmat(color: Color, additive := false, billboard := true) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), additive, billboard]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true  # inactive particles have zero scale; without this they render as black discs
		m.albedo_texture = Assets.soft_texture()
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	_mats[key] = m
	return m

static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / maxf(1.0, cols.size() - 1.0))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	return g

static func _quad(size: float, m: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q

static func _base(parent: Node, pos: Vector3, amount: int, lifetime: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	if one_shot:
		p.explosiveness = 0.9
		p.finished.connect(p.queue_free)
	p.emitting = true
	return p

static func fire(parent: Node, pos: Vector3, size := 1.0) -> CPUParticles3D:
	var p := _base(parent, pos, int(22 * size) + 8, 0.8, false)
	p.mesh = _quad(1.0 * size, pmat(Color(1, 1, 1)))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45 * size
	p.direction = Vector3.UP
	p.spread = 18.0
	p.gravity = Vector3(0, 3.0, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = curve
	p.color_ramp = _ramp([Color(1.0, 0.95, 0.55, 1.0), Color(1.0, 0.6, 0.1, 1.0), Color(0.9, 0.25, 0.05, 0.8), Color(0.3, 0.1, 0.05, 0.0)])
	var smoke := _base(p, pos + Vector3(0, 1.3 * size, 0), int(5 * size) + 3, 2.2, false)
	smoke.mesh = _quad(1.3 * size, pmat(Color(1, 1, 1)))
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.gravity = Vector3(0.4, 1.2, 0)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.2
	smoke.color_ramp = _ramp([Color(0.5, 0.47, 0.45, 0.0), Color(0.5, 0.47, 0.45, 0.35), Color(0.65, 0.65, 0.65, 0.0)])
	return p

static func explosion(parent: Node, pos: Vector3, size := 1.0) -> void:
	var p := _base(parent, pos, int(70 * size), 1.6, true)
	p.mesh = _quad(2.6 * size, pmat(Color(1, 1, 1)))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5 * size
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 4.0 * size
	p.initial_velocity_max = 11.0 * size
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.gravity = Vector3(0, 1.0, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.0
	p.color_ramp = _ramp([Color(1, 0.97, 0.75, 1), Color(1, 0.6, 0.1, 1), Color(0.85, 0.25, 0.05, 0.85), Color(0.2, 0.1, 0.08, 0)])
	var s := _base(parent, pos + Vector3(0, 1.5, 0), int(30 * size), 4.0, true)
	s.mesh = _quad(3.5 * size, pmat(Color(1, 1, 1)))
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 2.0 * size
	s.direction = Vector3.UP
	s.spread = 60.0
	s.initial_velocity_min = 2.0
	s.initial_velocity_max = 6.0 * size
	s.damping_min = 1.0
	s.damping_max = 2.0
	s.gravity = Vector3(0, 0.8, 0)
	s.color_ramp = _ramp([Color(0.45, 0.4, 0.37, 0.75), Color(0.55, 0.52, 0.5, 0.45), Color(0.7, 0.7, 0.7, 0)])
	debris(parent, pos, Color(0.35, 0.28, 0.22), int(26 * size), 9.0 * size)

static func debris(parent: Node, pos: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := _base(parent, pos + Vector3(0, 0.5, 0), amount, 1.6, true)
	var b := BoxMesh.new()
	b.size = Vector3(0.3, 0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	b.material = m
	p.mesh = b
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -18, 0)
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4

static func sparkle(parent: Node, pos: Vector3, color: Color, amount := 24, radius := 1.0) -> void:
	var p := _base(parent, pos, amount, 1.2, true)
	p.explosiveness = 0.6
	p.mesh = _quad(0.35, pmat(Color(1, 1, 1), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 30.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.5
	p.color_ramp = _ramp([Color(color, 1.0), Color(color, 0.8), Color(color, 0.0)])

static func beam(parent: Node, pos: Vector3, color: Color) -> void:
	var p := _base(parent, pos, 40, 1.0, true)
	p.explosiveness = 0.2
	p.mesh = _quad(0.5, pmat(Color(1, 1, 1), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.6, 4.0, 0.6)
	p.gravity = Vector3(0, -3, 0)
	p.color_ramp = _ramp([Color(color, 0.0), Color(color, 0.9), Color(color, 0.0)])

static func dust(parent: Node, pos: Vector3) -> void:
	var p := _base(parent, pos + Vector3(0, 0.2, 0), 16, 1.2, true)
	p.mesh = _quad(0.9, pmat(Color(1, 1, 1)))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.color_ramp = _ramp([Color(0.85, 0.78, 0.62, 0.7), Color(0.85, 0.78, 0.62, 0.0)])

static func soul(parent: Node, pos: Vector3) -> void:
	var p := _base(parent, pos + Vector3(0, 0.5, 0), 8, 1.6, true)
	p.mesh = _quad(0.3, pmat(Color(1, 1, 1), true))
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.2
	p.color_ramp = _ramp([Color(0.8, 0.9, 1.0, 0.9), Color(0.8, 0.9, 1.0, 0.0)])

static func rain(parent: Node, extent: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 420
	p.lifetime = 0.9
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	var b := BoxMesh.new()
	b.size = Vector3(0.07, 0.9, 0.07)
	b.material = pmat(Color(0.55, 0.7, 1.0, 0.85), false, false)
	p.mesh = b
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(extent, 0.3, extent)
	p.direction = Vector3.DOWN
	p.spread = 2.0
	p.gravity = Vector3(0, -10, 0)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 16.0
	p.color = Color(0.75, 0.85, 1.0, 0.7)
	p.emitting = true
	return p
