@tool
extends EditorPlugin

enum PaintState {
	Off,
	Add,
	Remove,
}

var dock_scene = preload("res://addons/tilebrush/dock.tscn")
var dock: TileBrushDock

# selected tilemap
var tilemap: TileMapLayer
var tileset_idx: int = -1
var terrain_idx: int = -1

# brush settings
var brush_shape: TileBrushCommon.BrushShape
var brush_settings: Dictionary[TileBrushCommon.BrushSetting, Variant] = { }
var brush_size: Vector2i = Vector2i(3, 3)
var density: float = 1

# state
var shape: TileBrushShape.Shape
var paint_state: PaintState = PaintState.Off
var stroke_cells: Dictionary[Vector2i, bool] = { }
var last_cell: Vector2i
var hover_cell: Vector2i
var actions: Dictionary[Vector2i, Dictionary] = { }

####################
# Editor plugin
####################


func _enter_tree() -> void:
	# create the dock
	dock = dock_scene.instantiate()
	add_control_to_bottom_panel(dock, "TileBrush")

	# connect up signals
	dock.brush_changed.connect(_on_brush_changed)
	dock.density_changed.connect(_on_density_changed)
	dock.terrain_selected.connect(_on_terrain_selected)

	# set initial state
	shape = TileBrushShape.Shape.ellipse(brush_size)

	# ensure we get mouse events, as TileMapLayer can consume them
	set_input_event_forwarding_always_enabled()

	print("TileBrush plugin loaded")


func _exit_tree() -> void:
	# remove the dock
	remove_control_from_bottom_panel(dock)
	dock.queue_free()


func _edit(object: Object) -> void:
	# update the tilemap to the selected object
	_set_tilemap(object as TileMapLayer)


func _handles(object: Object) -> bool:
	# we only handle if the selected object is a TileMapLayer
	return object is TileMapLayer


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	# do not consume input if we are not active
	if not _is_active():
		return false
	if not tilemap:
		return false

	# update the overlay position on mouse move
	var handled_mouse_move: bool = false
	if _is_mouse_moved(event):
		var cell = _screen_to_cell(event.position)
		if cell != hover_cell:
			hover_cell = cell
			handled_mouse_move = true
			update_overlays()

	if paint_state == PaintState.Off and _is_mouse_pressed(event):
		if event.alt_pressed:
			_eyedrop(_screen_to_cell(event.position))
			return true
		elif event.ctrl_pressed:
			paint_state = PaintState.Remove
		else:
			paint_state = PaintState.Add
		var cell: Vector2i = _screen_to_cell(event.position)
		update_overlays()
		last_cell = cell
		get_undo_redo().create_action("Tile Brush Stroke")
		_paint_at(cell)
		return true
	elif paint_state != PaintState.Off and _is_mouse_released(event):
		stroke_cells.clear()
		paint_state = PaintState.Off
		update_overlays()
		# stop painting on mouse release
		# commit the undo action, but do not execute it as we
		# have already dynamically updated the cells
		# create redo/undo actions for this part of the stroke
		var ur = get_undo_redo()
		for cell in actions:
			ur.add_do_method(self, "_set_cell_state", tilemap, cell, _get_cell_state(tilemap, cell))
			ur.add_undo_method(self, "_set_cell_state", tilemap, cell, actions[cell])
		actions.clear()
		get_undo_redo().commit_action(false)
		return true
	elif paint_state != PaintState.Off and _is_mouse_moved(event):
		# paint from previous position to current position on mouse move
		var cell = _screen_to_cell(event.position)
		_paint_line(last_cell, cell)
		last_cell = cell
		update_overlays()
		return true

	# did not consume the event
	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	# do not draw anything if we are not active
	if not _is_active():
		return
	if not tilemap:
		return

	# draw an overlay of where the brushstroke would paint
	_draw_brush_preview(overlay)

####################
# Signal handlers
####################


func _create_brush() -> void:
	match brush_shape:
		TileBrushCommon.BrushShape.Ellipse:
			shape = TileBrushShape.Shape.ellipse(brush_size)
		TileBrushCommon.BrushShape.Rectangle:
			shape = TileBrushShape.Shape.rectangle(
				brush_size,
				brush_settings.get(TileBrushCommon.BrushSetting.CornerRadius, 0),
			)
		TileBrushCommon.BrushShape.Diamond:
			shape = TileBrushShape.Shape.diamond(brush_size)
		TileBrushCommon.BrushShape.Cross:
			shape = TileBrushShape.Shape.cross(
				brush_size,
				brush_settings.get(TileBrushCommon.BrushSetting.HorizontalBeamThickness, 1),
				brush_settings.get(TileBrushCommon.BrushSetting.VerticalBeamThickness, 1),
			)

	if brush_settings.get(TileBrushCommon.BrushSetting.Fill, false):
		shape.flood_fill()
	if brush_settings.get(TileBrushCommon.BrushSetting.BorderThickness):
		var t: int = brush_settings[TileBrushCommon.BrushSetting.BorderThickness]
		# the user selects the desired thickness, but our shape algorithm
		# _increases_ the thickness. as the shape is built with border radius
		# of 1, we thicken by t-1
		shape.thicken(t - 1)


func _on_brush_changed(s: TileBrushCommon.BrushShape, d: Vector2i, o: Dictionary[TileBrushCommon.BrushSetting, Variant]) -> void:
	brush_shape = s
	brush_size = d
	brush_settings = o
	_create_brush()
	update_overlays()


func _on_density_changed(v: float) -> void:
	density = v


func _on_terrain_selected(si: int, ti: int) -> void:
	tileset_idx = si
	terrain_idx = ti

####################
# Utils
####################


# returns true if the plugin is active
func _is_active() -> bool:
	return dock and dock.is_visible_in_tree()


# returns true for a left mouse button press event
func _is_mouse_pressed(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	if not event.is_pressed():
		return false
	return true


# returns true for a left mouse button release event
func _is_mouse_released(event: InputEvent) -> bool:
	if not event is InputEventMouseButton:
		return false
	if not event.is_released():
		return false
	return true


# returns true for a mouse move event
func _is_mouse_moved(event: InputEvent) -> bool:
	return event is InputEventMouseMotion


# set the active tilemap to the given object
func _set_tilemap(tm: TileMapLayer):
	tilemap = tm
	tileset_idx = -1
	terrain_idx = -1
	dock.set_tilemap(tm)


# retrieve the cell at the given screen coordinates
func _screen_to_cell(pos: Vector2) -> Vector2i:
	var vp = get_editor_interface().get_editor_viewport_2d()
	var world = vp.get_final_transform().affine_inverse() * pos
	var local: Vector2 = tilemap.to_local(world)
	return tilemap.local_to_map(local)


# return the screen coordinates of a given cell
func _cell_to_screen(cell: Vector2i) -> Vector2:
	var local = tilemap.map_to_local(cell)
	var world = tilemap.to_global(local)
	var vp = get_editor_interface().get_editor_viewport_2d()
	return vp.get_final_transform() * world


# draws the overlay of where the brush would paint
func _draw_brush_preview(overlay):
	if tileset_idx < 0 or terrain_idx < 0:
		return

	var c: Color
	var cells: Array[Vector2i]

	if Input.is_key_pressed(KEY_CTRL):
		c = Color(1, 0.3, 0.3)
		cells = shape.to_array(hover_cell)
	elif Input.is_key_pressed(KEY_ALT):
		c = Color(0.3, 0.3, 1)
		cells = [hover_cell]
	else:
		c = tilemap.tile_set.get_terrain_color(tileset_idx, terrain_idx)
		cells = shape.to_array(hover_cell)

	# get the size of a single cell in screen coordinates
	var vp = get_editor_interface().get_editor_viewport_2d()
	var xform = vp.get_final_transform()
	var tile_size_world = tilemap.tile_set.tile_size
	var tile_size_screen = xform.basis_xform(tile_size_world)

	# iterate over all cells in the brush, painting a square on the
	# screen at its position
	for cell in cells:
		var screen_pos = _cell_to_screen(cell)
		var rect = Rect2(
			screen_pos - tile_size_screen * 0.5,
			tile_size_screen,
		)
		overlay.draw_rect(rect, Color(c.r, c.g, c.b, 0.4))


# paints the current TileMapLayer using the selected terrain
# and brush settings
func _paint_at(center: Vector2i):
	# safety; make sure there is a terrain selected
	if tileset_idx < 0 or terrain_idx < 0:
		return

	# get all the cells which the current brush would paint
	var brush_cells = shape.to_array(center)

	# apply the brush density to these cells; this removes cells
	# from brush_cells in order to get the fraction of cells which
	# we will paint to match the density, and returns
	# the removed cells
	var empty_cells = _apply_density_to_cells(brush_cells)

	# calculate the set of cells we are going to paint by filtering
	# out any cells which have already been painted; this is both for
	# efficiency and to make sure we don't paint over any cells which
	# were skipped due to the brush density. also save the state of the
	# cell before in the actions dictionary so that we can create the
	# undo redo action
	var cells: Array[Vector2i] = []
	for cell in brush_cells:
		if not stroke_cells.has(cell):
			stroke_cells[cell] = true
			# as set_cells_terrain_connect can also affect neighbours,
			# we need to add all neighbour cells to the action too
			for x in range(-1, 2):
				for y in range(-1, 2):
					var c = cell + Vector2i(x, y)
					if not actions.has(c):
						actions[c] = _get_cell_state(tilemap, c)
			cells.append(cell)

	# mark all the 'empty' cells as painted too, so we don't paint over
	# them later in the stroke
	for cell in empty_cells:
		stroke_cells[cell] = true

	# paint the cells onto the tilemap
	var idx = terrain_idx
	match paint_state:
		PaintState.Add:
			tilemap.set_cells_terrain_connect(cells, tileset_idx, idx, true)
		PaintState.Remove:
			for cell in cells:
				tilemap.set_cell(cell)


# get the state of the given cell
func _get_cell_state(tm: TileMapLayer, cell: Vector2i) -> Dictionary:
	return {
		"source_id": tm.get_cell_source_id(cell),
		"atlas_coords": tm.get_cell_atlas_coords(cell),
		"alternative_tile": tm.get_cell_alternative_tile(cell),
	}


# set the state of the given cell
func _set_cell_state(tm: TileMapLayer, cell: Vector2i, state: Dictionary):
	tm.set_cell(
		cell,
		state["source_id"],
		state["atlas_coords"],
		state["alternative_tile"],
	)


# removes [cells.size() * brush_density] cells from the array,
# returning the cells which were removed
func _apply_density_to_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var will_paint: Array[Vector2i] = []
	var wont_paint: Array[Vector2i] = []

	# iterate through cells, sorting them into will/won't paint
	for cell in cells:
		if randf() <= density:
			will_paint.append(cell)
		else:
			wont_paint.append(cell)

	# update the input array with will_paint, and return the wont_paint
	cells.assign(will_paint)
	return wont_paint


# paint a brush stroke from last_cell to cell
func _paint_line(last_cell: Vector2i, cell: Vector2i):
	# calculate the number of steps which we need to make to
	# ensure we don't miss any cells
	var dx = abs(cell.x - last_cell.x)
	var dy = abs(cell.y - last_cell.y)
	var steps = max(dx, dy)
	if steps == 0:
		return

	# iterate between last_cell and cell, interpolating the brush position
	# and calling _paint_at
	for i in range(1, steps + 1):
		var t = float(i) / steps
		var x = roundi(lerp(last_cell.x, cell.x, t))
		var y = roundi(lerp(last_cell.y, cell.y, t))
		_paint_at(Vector2i(x, y))


func _eyedrop(cell: Vector2i) -> void:
	if not tilemap:
		return

	var source_id := tilemap.get_cell_source_id(cell)
	if source_id < 0:
		return

	var atlas_coords := tilemap.get_cell_atlas_coords(cell)
	var alt := tilemap.get_cell_alternative_tile(cell)

	var ts: TileSet = tilemap.tile_set
	var source := ts.get_source(source_id) as TileSetAtlasSource
	if not source:
		return

	var tile_data := source.get_tile_data(atlas_coords, alt)
	if not tile_data:
		return

	var terrain_set := tile_data.terrain_set
	var terrain := tile_data.terrain

	if terrain_set < 0 or terrain < 0:
		return # not a terrain tile

	self.tileset_idx = terrain_set
	self.terrain_idx = terrain

	self.dock.select_terrain(terrain_set, terrain)
