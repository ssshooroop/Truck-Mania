extends SceneTree
## Imported artwork must fit the same body used by collision and touch rules.
## These checks also keep real cargo sprites inside each normalized truck bed.

const Model = preload("res://scripts/game_model.gd")
const Sprites = preload("res://scripts/vehicle_sprites.gd")
const Cargo = preload("res://scripts/cargo_sprites.gd")
const MEASURED_LENGTHS := [98.24,139.37,182.79]
# Every prepared cargo image is fitted within this shared maximum extent.
const CARGO_FOOTPRINT := Vector2(26, 28.4)
const EPSILON := 0.001
const SOURCE_NAMES := [
	"Blue-pickup.png", "Pickup-recolor-base.png", "Green Dump Truck.png",
	"Orange Dump Truck.png", "Red Flatbed Truck.png"
]

var checks := 0
var failures := 0

func _initialize() -> void:
	var sources: Dictionary = {}
	for kind in range(Model.CAPACITIES.size()):
		for material_id in range(Model.COLORS):
			_test_variant(kind, material_id, sources)
	check(sources.size() == SOURCE_NAMES.size(), "Every supplied truck drawing is used")
	for filename: String in SOURCE_NAMES:
		check(sources.has(filename), "The fleet includes %s" % filename)
	for material_id in range(Model.COLORS):
		_test_cargo(material_id)
	print("Vehicle and cargo sprite checks: %d; variants: 18; supplied drawings: %d; failures: %d" % [checks, sources.size(), failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _encloses(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(EPSILON).encloses(inner)

func _expected_source(kind: int, material_id: int) -> String:
	if kind == 0:
		return "Blue-pickup.png" if material_id == 4 else "Pickup-recolor-base.png"
	if kind == 2:
		return "Red Flatbed Truck.png"
	return "Orange Dump Truck.png" if material_id in [0, 1] else "Green Dump Truck.png"

func _test_variant(kind: int, material_id: int, sources: Dictionary) -> void:
	var label := "kind=%d material=%d" % [kind, material_id]
	var source: String = Sprites.source_path(kind, material_id)
	var filename := source.get_file()
	sources[filename] = true
	check(filename == _expected_source(kind, material_id), "%s uses its intended supplied drawing" % label)
	check(FileAccess.file_exists(source), "%s source exists" % label)
	var texture: Texture2D = Sprites.get_texture(kind, material_id)
	check(texture != null, "%s has an imported texture" % label)
	if texture == null:
		return
	check(texture.get_width() > 0 and texture.get_height() > 0, "%s texture has positive dimensions" % label)
	var image: Image = texture.get_image()
	check(image != null and not image.is_empty(), "%s texture exposes real pixels" % label)
	if image != null and not image.is_empty():
		if image.is_compressed():
			check(image.decompress() == OK, "%s pixels can be inspected" % label)
		check(image.detect_alpha() != Image.ALPHA_NONE, "%s has a transparent background" % label)
		var corners: Array[Vector2i] = [Vector2i.ZERO,
			Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1),
			Vector2i(image.get_width() - 1, image.get_height() - 1)]
		for corner: Vector2i in corners:
			check(image.get_pixelv(corner).a <= 0.01, "%s has no opaque background corner at %s" % [label, corner])
		check(image.get_used_rect().has_area(), "%s contains visible vehicle pixels" % label)

	var rect: Rect2 = Sprites.draw_rect(kind, material_id)
	var model_size := Vector2(Model.WIDTHS[kind], Model.LENGTHS[kind])
	var footprint := Rect2(-model_size * 0.5, model_size)
	check(rect.size.x > 0 and rect.size.y > 0 and is_finite(rect.size.x) and is_finite(rect.size.y),
		"%s draw size is finite and positive" % label)
	check(rect.get_center().length() <= EPSILON, "%s rotates around the centered vehicle" % label)
	check(_encloses(footprint, rect), "%s artwork stays inside its collision and touch body" % label)
	check(absf(rect.size.x - 56.0) <= EPSILON, "%s has the common 56px width" % label)
	check(absf(rect.size.y - MEASURED_LENGTHS[kind]) <= EPSILON,
		"%s uses the length measured from the supplied layout" % label)
	check(rect.size.is_equal_approx(model_size), "%s collision size matches the normalized drawing" % label)

	var bed: Rect2 = Sprites.bed_rect(kind, material_id)
	check(bed.has_area(), "%s has a usable cargo bed" % label)
	check(_encloses(rect, bed), "%s cargo bed stays within the pictured vehicle" % label)
	var slots: Array[Vector2] = Sprites.cargo_slots(kind, material_id)
	check(slots.size() == Model.CAPACITIES[kind], "%s shows one cargo position per real capacity unit" % label)
	var cargo_scale: float = Sprites.cargo_scale(kind, material_id)
	check(cargo_scale > 0 and is_finite(cargo_scale), "%s cargo scale is finite and positive" % label)
	var cargo_size := CARGO_FOOTPRINT * cargo_scale
	for index in range(slots.size()):
		var cargo_rect := Rect2(slots[index] - cargo_size * 0.5, cargo_size)
		check(_encloses(bed, cargo_rect), "%s cargo unit %d stays wholly in the bed" % [label, index + 1])
		check(_encloses(footprint, cargo_rect), "%s cargo unit %d stays inside vehicle clearance" % [label, index + 1])

func _test_cargo(material_id: int) -> void:
	var label := "cargo=%d" % material_id
	var source: Texture2D = Cargo.SOURCES[material_id]
	check(FileAccess.file_exists(source.resource_path), "%s supplied PNG exists" % label)
	var texture: Texture2D = Cargo.get_texture(material_id)
	check(texture != null, "%s has a prepared texture" % label)
	check(texture == Cargo.get_texture(material_id), "%s reuses its cached texture" % label)
	if texture == null:
		return
	var image: Image = texture.get_image()
	check(image != null and not image.is_empty(), "%s texture contains pixels" % label)
	if image == null or image.is_empty():
		return
	check(image.detect_alpha() != Image.ALPHA_NONE, "%s keeps a transparent silhouette" % label)
	check(image.has_mipmaps(), "%s has mipmaps for small phone-sized artwork" % label)
	check(image.get_used_rect().has_area(), "%s includes visible cargo" % label)
	var rect: Rect2 = Cargo.draw_rect(material_id)
	check(rect.has_area(), "%s has a positive draw size" % label)
	check(rect.get_center().length() <= EPSILON, "%s is centered at its cargo position" % label)
	check(_encloses(Rect2(-CARGO_FOOTPRINT*0.5,CARGO_FOOTPRINT),rect),
		"%s stays inside the shared cargo footprint" % label)
	var original: Image = source.get_image()
	if original.is_compressed(): original.decompress()
	var used: Rect2i = original.get_used_rect()
	var aspect: float = float(used.size.x)/used.size.y
	check(absf(rect.size.x/rect.size.y-aspect) <= EPSILON,
		"%s preserves the source silhouette proportions" % label)
