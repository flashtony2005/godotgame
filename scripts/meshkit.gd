extends RefCounted

## 全部模型都用基础几何体拼，不依赖任何外部资源文件——和原版「无 asset」的思路一致。

static var _cache := {}

static func mat(c: Color, glow: float = 0.0, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [c.to_html(), glow, rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_cache[key] = m
	return m

static func _put(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot: Vector3, scale: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _put(parent, bm, mat(c, glow), pos, rot, Vector3.ONE)

static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, c: Color, sides := 8, rot := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	return _put(parent, cm, mat(c, glow), pos, rot, Vector3.ONE)

static func cone(parent: Node3D, radius: float, height: float, pos: Vector3, c: Color, sides := 8, rot := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	cm.rings = 1
	return _put(parent, cm, mat(c, glow), pos, rot, Vector3.ONE)

static func sphere(parent: Node3D, radius: float, pos: Vector3, c: Color, seg := 8, glow := 0.0) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = seg
	sm.rings = max(3, seg / 2)
	return _put(parent, sm, mat(c, glow), pos, Vector3.ZERO, Vector3.ONE)

static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 8
	cm.rings = 4
	return _put(parent, cm, mat(c), pos, rot, Vector3.ONE)

static func pivot(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

## 简易「地形块」：一根轻微倾斜的柱子，用来拼岩石/树桩
static func slab(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	return box(parent, size, pos, c, rot)
