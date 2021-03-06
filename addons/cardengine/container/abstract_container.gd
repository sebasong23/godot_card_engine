class_name AbstractContainer
extends Control

const CARD_NODE_FMT = "card_%s"

enum LayoutMode {GRID, PATH}
enum FineTuningMode {LINEAR, SYMMETRIC, RANDOM}
enum AspectMode {KEEP, IGNORE}

export(PackedScene) var card_visual: PackedScene = null
export(NodePath) var in_anchor: NodePath = ""
export(NodePath) var out_anchor: NodePath = ""

var _store: AbstractStore = null

var _layout_mode = LayoutMode.GRID
var _face_up: float = true

# Grid parameters
var _grid_card_width: float = 200
var _grid_fixed_width: bool = true
var _grid_card_spacing: Vector2 = Vector2(0.75, 1.2)
var _grid_halign: int = HALIGN_CENTER
var _grid_valign: int = VALIGN_CENTER
var _grid_columns: int = -1
var _grid_expand: bool = true

# Path parameters
var _path_card_width: float = 200
var _path_fixed_width: bool = false
var _path_spacing: float = 0.5

# Position fine tuning
var _fine_pos: bool = false
var _fine_pos_mode = FineTuningMode.SYMMETRIC
var _fine_pos_min: Vector2 = Vector2(0.0, 0.0)
var _fine_pos_max: Vector2 = Vector2(0.0, 60.0)

# Angle fine tuning
var _fine_angle: bool = false
var _fine_angle_mode = FineTuningMode.RANDOM
var _fine_angle_min: float = deg2rad(-10.0)
var _fine_angle_max: float = deg2rad(10.0)

# Scale fine tuning
var _fine_scale: bool = false
var _fine_scale_mode = FineTuningMode.RANDOM
var _fine_scale_ratio = AspectMode.KEEP
var _fine_scale_min: Vector2 = Vector2(0.85, 0.85)
var _fine_scale_max: Vector2 = Vector2(1.15, 1.15)

# Transitions
var _transitions: CardTransitions = CardTransitions.new()

onready var _cards = $Cards
onready var _path = $CardPath


func store() -> AbstractStore:
	return _store


func set_store(store: AbstractStore) -> void:
	_store = store
	_store.connect("card_added", self, "_update_container")
	_store.connect("card_removed", self, "_update_container")
	_store.connect("cards_removed", self, "_update_container")
	_store.connect("filtered", self, "_update_container")
	_store.connect("sorted", self, "_update_container")
	_update_container()


func _update_container() -> void:
	if card_visual == null:
		return
	
	if _store == null:
		return
	
	_clear()
	
	if not in_anchor.is_empty():
		var anchor = get_node(in_anchor)
		if anchor is Node2D:
			_transitions.in_anchor.enabled = true
			_transitions.in_anchor.position = anchor.position
			_transitions.in_anchor.scale = anchor.scale
			_transitions.in_anchor.rotation = anchor.rotation
		elif anchor is Control:
			_transitions.in_anchor.enabled = true
			_transitions.in_anchor.position = anchor.rect_position
			_transitions.in_anchor.scale = anchor.rect_scale
			_transitions.in_anchor.rotation = deg2rad(anchor.rect_rotation)
	
	if not out_anchor.is_empty():
		var anchor = get_node(out_anchor)
		if anchor is Node2D:
			_transitions.out_anchor.enabled = true
			_transitions.out_anchor.position = anchor.position
			_transitions.out_anchor.scale = anchor.scale
			_transitions.out_anchor.rotation = anchor.rotation
		elif anchor is Control:
			_transitions.out_anchor.enabled = true
			_transitions.out_anchor.position = anchor.rect_position
			_transitions.out_anchor.scale = anchor.rect_scale
			_transitions.out_anchor.rotation = deg2rad(anchor.rect_rotation)
	
	# Adding missing cards
	for card in _store.cards():
		if _cards.find_node(CARD_NODE_FMT % card.ref(), false, false) != null:
			continue
			
		var visual_inst := card_visual.instance()
		if not visual_inst is AbstractCard:
			printerr("Container visual instance must inherit AbstractCard")
			continue
		
		visual_inst.name = CARD_NODE_FMT % card.ref()
		_cards.add_child(visual_inst)
		visual_inst.set_instance(card)
		visual_inst.set_transitions(_transitions)
		visual_inst.connect("need_removal", self, "_on_need_removal", [visual_inst])
		
		if _face_up:
			visual_inst.flip(AbstractCard.CardSide.FRONT)
		else:
			visual_inst.flip(AbstractCard.CardSide.BACK)
	
	# Sorting according to store order
	var index = 0
	for card in _store.cards():
		var visual = _cards.find_node(CARD_NODE_FMT % card.ref(), false, false)
		_cards.move_child(visual, index)
		index += 1
	
	_layout_cards()


func _layout_cards():
	var card_index: int = 0
	
	for child in _cards.get_children():
		if child is AbstractCard && not child.is_flagged_for_removal():
			var state = CardState.new()
			
			match _layout_mode:
				LayoutMode.GRID:
					_grid_layout(state, card_index, child.size)
				LayoutMode.PATH:
					_path_layout(state, card_index, child.size)
		
			_fine_tune(state, card_index, child.size)
			
			child.set_root_state(state)
			card_index += 1


func _grid_layout(state: CardState, grid_cell: int, card_size: Vector2):
	var width_ratio: float = 0.0
	var height_adjusted: float = 0.0
	var row_width: float = 0.0
	var col_height: float = 0.0
	var grid_offset: Vector2 = Vector2(0.0, 0.0)
	var spacing_offset: Vector2 = Vector2(0.0, 0.0)
	
	# Card size
	if not _grid_fixed_width:
		if _grid_columns > 0:
			_grid_card_width = rect_size.x / (_grid_columns * _grid_card_spacing.x)
		else:
			_grid_card_width = rect_size.x / (_store.count() * _grid_card_spacing.x)
	
	width_ratio = _grid_card_width / card_size.x
	height_adjusted = card_size.y * width_ratio
	
	# Grid offset
	if _grid_columns > 0:
		row_width = _grid_columns * _grid_card_width * _grid_card_spacing.x
		col_height = ceil(_store.count() / float(_grid_columns)) * height_adjusted * _grid_card_spacing.y
	else:
		row_width = _store.count() * _grid_card_width * _grid_card_spacing.x
		col_height = height_adjusted * _grid_card_spacing.y
	
	if _grid_expand:
		if row_width > rect_size.x:
			rect_min_size.x = row_width
		
		if col_height > rect_size.y || _grid_columns > 0:
			rect_min_size.y = col_height
	
	spacing_offset.x = (_grid_card_width * _grid_card_spacing.x - _grid_card_width) / 2.0
	spacing_offset.y = (height_adjusted * _grid_card_spacing.y - height_adjusted) / 2.0
	
	match _grid_halign:
		HALIGN_LEFT:
			grid_offset.x = spacing_offset.x
		HALIGN_CENTER:
			grid_offset.x = spacing_offset.x + (rect_size.x - row_width) / 2.0
		HALIGN_RIGHT:
			grid_offset.x = spacing_offset.x + (rect_size.x - row_width)
			
	match _grid_valign:
		VALIGN_TOP:
			grid_offset.y = spacing_offset.y
		VALIGN_CENTER:
			grid_offset.y = spacing_offset.y + (rect_size.y - col_height) / 2.0
		VALIGN_BOTTOM:
			grid_offset.y = spacing_offset.y + (rect_size.y - col_height)
	
	var pos: Vector2 = Vector2(0.0 , 0.0)
	# Initial pos
	pos.x = _grid_card_width / 2.0
	pos.y = height_adjusted / 2.0
	
	# Cell align pos
	if _grid_columns > 0:
		pos.x += _grid_card_width * _grid_card_spacing.x * (grid_cell % _grid_columns)
		pos.y += height_adjusted * _grid_card_spacing.y * ceil(grid_cell / _grid_columns)
	else:
		pos.x += _grid_card_width * _grid_card_spacing.x * grid_cell
	
	# Grid align pos
	pos.x += grid_offset.x
	pos.y += grid_offset.y
	
	state.scale = Vector2(width_ratio, width_ratio)
	state.pos = pos


func _path_layout(state: CardState, card_index: int, card_size: Vector2):
	var width_ratio: float = 0.0
	var curve: Curve2D = _path.get_curve()
	var path_length: float = curve.get_baked_length()
	var path_offset: float = 0.0
	var path_offset_delta: float = 0.0
	
	if not _path_fixed_width:
		_path_card_width = path_length / (_store.count() * _path_spacing)
	
	width_ratio = _path_card_width / card_size.x

	# Path offset
	path_offset_delta = path_length - _path_card_width
	path_offset_delta /= _store.count() - 1
	path_offset = _path_card_width / 2 + path_offset_delta * card_index
	
	state.scale =  Vector2(width_ratio, width_ratio)
	state.pos = curve.interpolate_baked(path_offset)


func _fine_tune(state: CardState, card_index: int, card_size: Vector2):
	var card_count: float = _store.count() - 1
	
	if _fine_pos:
		match _fine_pos_mode:
			FineTuningMode.LINEAR:
				state.pos += lerp(
					_fine_pos_min,
					_fine_pos_max,
					card_index / card_count)
			FineTuningMode.SYMMETRIC:
				state.pos += lerp(
					_fine_pos_min,
					_fine_pos_max,
					abs(((card_index * 2.0) / card_count) - 1.0))
			FineTuningMode.RANDOM:
				state.pos += Vector2(
					_fine_pos_min.x + randf() * (_fine_pos_max.x - _fine_pos_min.x),
					_fine_pos_min.y + randf() * (_fine_pos_max.y - _fine_pos_min.y))
	
	if _fine_angle:
		match _fine_angle_mode:
			FineTuningMode.LINEAR:
				state.rot += lerp_angle(
					_fine_angle_min,
					_fine_angle_max,
					card_index / card_count)
			FineTuningMode.SYMMETRIC:
				state.rot += lerp_angle(
					_fine_angle_min,
					_fine_angle_max,
					abs(((card_index * 2.0) / card_count) - 1.0))
			FineTuningMode.RANDOM:
				state.rot += _fine_angle_min + randf() * (_fine_angle_max - _fine_angle_min)
	
	if _fine_scale:
		match _fine_scale_mode:
			FineTuningMode.LINEAR:
				state.scale += lerp(
					_fine_scale_min,
					_fine_scale_max,
					card_index / card_count)
			FineTuningMode.SYMMETRIC:
				state.scale += lerp(
					_fine_scale_min,
					_fine_scale_max,
					abs(((card_index * 2.0) / card_count) - 1.0))
			FineTuningMode.RANDOM:
				match _fine_scale_ratio:
					AspectMode.IGNORE:
						state.scale += Vector2(
							_fine_scale_min.x + randf() * (_fine_scale_max.x - _fine_scale_min.x),
							_fine_scale_min.y + randf() * (_fine_scale_max.y - _fine_scale_min.y))
					AspectMode.KEEP:
						var random_scale = _fine_scale_min.x + randf() * (_fine_scale_max.x - _fine_scale_min.x)
						state.scale += Vector2(random_scale, random_scale)


func _clear() -> void:
	if _cards == null:
		return
	
	for child in _cards.get_children():
		if not _store.has_card(child.instance()):
			child.flag_for_removal()


func _on_AbstractContainer_resized() -> void:
	_update_container()


func _on_need_removal(card: AbstractCard) -> void:
	_cards.remove_child(card)
	card.queue_free()
