@tool
extends ScrollContainer

class_name TileBrushDock

####################
# Node References
####################

# terrain nodes
@onready var tile_map_name_label: LineEdit = %TileMapNameLabel
@onready var terrain_tree: Tree = %TerrainTree

# brush setting nodes
@onready var brush_shape_input: OptionButton = %BrushShapeInput
@onready var brush_width_input: SpinBox = %BrushWidthInput
@onready var brush_height_input: SpinBox = %BrushHeightInput
@onready var brush_size_link_button: Button = %BrushSizeLinkButton
@onready var brush_density_input: SpinBox = %BrushDensityInput
@onready var border_thickness_input: SpinBox = %BorderThicknessInput
@onready var brush_fill_checkbox: CheckBox = %BrushFillCheckBox

# dynamic setting nodes
@onready var options_container: GridContainer = %OptionsContainer
var brush_settings_common: Array[Node] = []
var get_extra_brush_settings := func() -> Dictionary[TileBrushCommon.BrushSetting, Variant]: return { }
var brush_settings_extra_nodes: Array[Node] = []

####################
# Signals
####################

signal brush_changed(
		shape: TileBrushCommon.BrushShape,
		size: Vector2i,
		settings: Dictionary[TileBrushCommon.BrushSetting, Variant],
)
signal density_changed(v: float)
signal terrain_selected(set_idx: int, terrain_idx: int)

####################
# ScrollContainer
####################


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	brush_shape_input.item_selected.connect(_on_brush_shape_changed)
	brush_width_input.value_changed.connect(_on_size_changed)
	brush_height_input.value_changed.connect(_on_size_changed)
	brush_size_link_button.toggled.connect(_on_brush_size_linked)
	border_thickness_input.value_changed.connect(func(_v): _on_brush_changed())
	brush_fill_checkbox.toggled.connect(func(_v): _on_brush_changed())
	brush_density_input.value_changed.connect(_on_density_changed)
	terrain_tree.item_selected.connect(_on_terrain_selected)

	brush_settings_common = [%BorderThicknessInput, %BrushFillCheckBox]

####################
# Signal handlers
####################


func _on_brush_size_linked(on: bool) -> void:
	var w: float = brush_width_input.value
	var h: float = brush_height_input.value
	if w != h:
		brush_width_input.value = min(w, h)
		brush_height_input.value = min(w, h)
		_on_brush_changed()


func _on_size_changed(v: float) -> void:
	if brush_size_link_button.button_pressed:
		brush_width_input.value = v
		brush_height_input.value = v
	_on_brush_changed()


func _on_brush_changed() -> void:
	var shape: TileBrushCommon.BrushShape = brush_shape_input.selected
	var width: int = ceili(brush_width_input.value)
	var height: int = ceili(brush_height_input.value)
	var settings: Dictionary[TileBrushCommon.BrushSetting, Variant] = get_extra_brush_settings.call()
	settings[TileBrushCommon.BrushSetting.Fill] = brush_fill_checkbox.button_pressed
	settings[TileBrushCommon.BrushSetting.BorderThickness] = ceili(border_thickness_input.value)

	brush_changed.emit(shape, Vector2i(width, height), settings)


func _on_density_changed(v: float) -> void:
	density_changed.emit(v)


func _on_brush_shape_changed(v: int) -> void:
	# remove any extra settings the old brush had
	# and initialise the new settings
	for node in brush_settings_extra_nodes:
		node.queue_free()
	match v:
		TileBrushCommon.BrushShape.Ellipse:
			_init_ellipse_brush_settings()
		TileBrushCommon.BrushShape.Rectangle:
			_init_rectangle_brush_settings()
		TileBrushCommon.BrushShape.Diamond:
			_init_diamond_brush_settings()
		TileBrushCommon.BrushShape.Cross:
			_init_cross_brush_settings()

	_on_brush_changed()


func _on_terrain_selected() -> void:
	var item: TreeItem = terrain_tree.get_selected()
	if not item:
		terrain_selected.emit(-1, -1)

	var data = item.get_metadata(0)
	if data["terrain"] < 0:
		return

	terrain_selected.emit(data["set"], data["terrain"])

####################
# Public methods
####################


func select_terrain(set_idx: int, terrain_idx: int) -> void:
	_select_in_subtree(terrain_tree.get_root(), set_idx, terrain_idx)


func set_tilemap(tilemap: TileMapLayer) -> void:
	terrain_tree.clear()
	var root := terrain_tree.create_item()

	if not tilemap:
		tile_map_name_label.text = ""
		var empty_set_item := terrain_tree.create_item(root)
		empty_set_item.set_text(0, "No terrain sets found")

	tile_map_name_label.text = tilemap.name

	var ts: TileSet = tilemap.tile_set
	var n_terrain_sets: int = ts.get_terrain_sets_count()
	if n_terrain_sets == 0:
		var empty_set_item := terrain_tree.create_item(root)
		empty_set_item.set_text(0, "No terrain sets found")

	for set_id in n_terrain_sets:
		var set_item := terrain_tree.create_item(root)

		var set_name = "Terrain Set %d" % set_id

		set_item.set_text(0, set_name)
		set_item.set_selectable(0, false)

		# Store ID for later retrieval
		set_item.set_metadata(0, { "set": set_id, "terrain": -1 })

		# Add terrains inside this set
		for terrain_id in ts.get_terrains_count(set_id):
			var terrain_item := terrain_tree.create_item(set_item)

			var terrain_colour = ts.get_terrain_color(set_id, terrain_id)
			var terrain_name = ts.get_terrain_name(set_id, terrain_id)
			if terrain_name.is_empty():
				terrain_name = "Terrain %d" % terrain_id

			terrain_item.set_text(0, terrain_name)
			terrain_item.set_icon(0, _make_colour_icon(terrain_colour))

			terrain_item.set_metadata(
				0,
				{
					"set": set_id,
					"terrain": terrain_id,
				},
			)

####################
# Utils
####################


func _select_in_subtree(item: TreeItem, set_id: int, terrain_id: int) -> bool:
	while item:
		var meta = item.get_metadata(0)
		if meta is Dictionary:
			if meta.get("set") == set_id and meta.get("terrain") == terrain_id:
				terrain_tree.set_selected(item, 0)
				terrain_tree.ensure_cursor_is_visible()
				return true

		if item.get_first_child():
			if _select_in_subtree(item.get_first_child(), set_id, terrain_id):
				return true

		item = item.get_next()

	return false


func _init_ellipse_brush_settings() -> void:
	get_extra_brush_settings = func() -> Dictionary[TileBrushCommon.BrushSetting, Variant]: return { }
	brush_settings_extra_nodes = []


func _init_rectangle_brush_settings() -> void:
	var corner_radius_label = Label.new()
	corner_radius_label.text = "Corner radius"
	options_container.add_child(corner_radius_label)
	var corner_radius_input = SpinBox.new()
	corner_radius_input.min_value = 0
	corner_radius_input.max_value = 100
	corner_radius_input.step = 1
	corner_radius_input.rounded = true
	options_container.add_child(corner_radius_input)
	corner_radius_input.value_changed.connect(func(_v): _on_brush_changed())

	get_extra_brush_settings = func() -> Dictionary[TileBrushCommon.BrushSetting, Variant]:
		return {
			TileBrushCommon.BrushSetting.CornerRadius: ceili(corner_radius_input.value),
		}
	brush_settings_extra_nodes = [
		corner_radius_label,
		corner_radius_input,
	]


func _init_diamond_brush_settings() -> void:
	get_extra_brush_settings = func() -> Dictionary[TileBrushCommon.BrushSetting, Variant]: return { }
	brush_settings_extra_nodes = []


func _init_cross_brush_settings() -> void:
	var beam_label = Label.new()
	beam_label.text = "Beam thickness"
	options_container.add_child(beam_label)
	var beam_container = HBoxContainer.new()
	options_container.add_child(beam_container)
	var hthickness_input = SpinBox.new()
	hthickness_input.min_value = 1
	hthickness_input.max_value = 100
	hthickness_input.step = 1
	hthickness_input.rounded = true
	hthickness_input.value_changed.connect(func(_v): _on_brush_changed())
	beam_container.add_child(hthickness_input)
	var by_label = Label.new()
	by_label.text = "x"
	beam_container.add_child(by_label)
	var vthickness_input = SpinBox.new()
	vthickness_input.min_value = 1
	vthickness_input.max_value = 100
	vthickness_input.step = 1
	vthickness_input.rounded = true
	vthickness_input.value_changed.connect(func(_v): _on_brush_changed())
	beam_container.add_child(vthickness_input)

	get_extra_brush_settings = func() -> Dictionary[TileBrushCommon.BrushSetting, Variant]:
		return {
			TileBrushCommon.BrushSetting.HorizontalBeamThickness: ceili(hthickness_input.value),
			TileBrushCommon.BrushSetting.VerticalBeamThickness: ceili(vthickness_input.value),
		}
	brush_settings_extra_nodes = [beam_label, beam_container]


func _make_colour_icon(color: Color) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)

	return ImageTexture.create_from_image(img)
