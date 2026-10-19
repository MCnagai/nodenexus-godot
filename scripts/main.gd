extends Control

signal context_pressed(world_position: Vector2)

const MAP_SIZE := Vector2(6000, 6000)
const GRID := 100.0
const MIN_ZOOM := 0.3
const MAX_ZOOM := 2.5
const HOLD_SECONDS := 0.5
const HOLD_SLOP := 12.0
const NODE_HALF_SIZE := Vector2(65, 32)
const PORT_HIT_RADIUS := 12.0

var camera_position := MAP_SIZE / 2.0
var camera_zoom := 1.0
# Temporary markers; replace with the live node collection when units are implemented.
var node_positions: Array[Vector2] = [Vector2(3000, 3000), Vector2(3300, 2800), Vector2(2600, 3200), Vector2(1500, 1800), Vector2(4700, 4400)]
var grass: ImageTexture
var node_style: StyleBoxFlat
var hud_style: StyleBoxFlat
var minimap_style: StyleBoxFlat
var touches: Dictionary = {}
var hold_origin := Vector2.ZERO
var hold_elapsed := 0.0
var hold_pending := false
var touch_right := false
var mouse_right := false
var gesture_blocked := false
var dragged_node := -1
var drag_offset := Vector2.ZERO
var node_drag_active := false
var drag_uses_touch := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    grass = _make_grass()
    node_style = _panel(Color("233b37"))
    hud_style = _panel(Color(0.06, 0.12, 0.10, 0.92))
    minimap_style = _panel(Color("122b23"))
    resized.connect(_refresh)
    _refresh()

func _make_grass() -> ImageTexture:
    var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    for y in range(128):
        for x in range(128):
            var shade := rng.randf_range(-0.035, 0.035)
            image.set_pixel(x, y, Color(0.24 + shade, 0.37 + shade, 0.19 + shade))
    for i in range(180):
        var x := rng.randi_range(1, 126)
        var y := rng.randi_range(3, 126)
        var color := Color(0.32, 0.45, 0.23) if i % 2 else Color(0.19, 0.31, 0.15)
        image.set_pixel(x, y, color)
        image.set_pixel(x, y - 1, color)
        image.set_pixel(x + 1, y - 2, color)
    return ImageTexture.create_from_image(image)

func screen_to_world(point: Vector2) -> Vector2:
    return camera_position + (point - size / 2.0) / camera_zoom

func visible_world_rect() -> Rect2:
    return Rect2(camera_position - size / camera_zoom / 2.0, size / camera_zoom)

func minimap_rect() -> Rect2:
    var side := minf(190.0, minf(size.x * 0.28, size.y * 0.32))
    return Rect2(size - Vector2(side + 18, side + 18), Vector2(side, side))

func _over_ui(point: Vector2) -> bool:
    return minimap_rect().grow(5).has_point(point) or Rect2(14, 14, minf(size.x - 28, 570), 116).has_point(point)

func _pick_node(screen_point: Vector2) -> int:
    var point := screen_to_world(screen_point)
    # Last drawn node wins when bodies overlap. Ports are reserved for wiring.
    for i in range(node_positions.size() - 1, -1, -1):
        var center := node_positions[i]
        if Rect2(center - NODE_HALF_SIZE, NODE_HALF_SIZE * 2).has_point(point):
            for side in [-1, 1]:
                if point.distance_to(center + Vector2(side * NODE_HALF_SIZE.x, 0)) <= PORT_HIT_RADIUS:
                    return -1
            return i
    return -1

func _begin_node_drag(point: Vector2, from_touch: bool) -> void:
    if _over_ui(point):
        return
    dragged_node = _pick_node(point)
    if dragged_node >= 0:
        drag_offset = node_positions[dragged_node] - screen_to_world(point)
        drag_uses_touch = from_touch
        node_drag_active = not from_touch
        queue_redraw()

func _end_node_drag() -> void:
    dragged_node = -1
    node_drag_active = false
    queue_redraw()

func _move_node(point: Vector2) -> void:
    var target := screen_to_world(point) + drag_offset
    node_positions[dragged_node] = target.clamp(NODE_HALF_SIZE, MAP_SIZE - NODE_HALF_SIZE)
    queue_redraw()

func _refresh() -> void:
    var half := size / camera_zoom / 2.0
    camera_position.x = clampf(camera_position.x, minf(half.x, MAP_SIZE.x / 2), maxf(MAP_SIZE.x - half.x, MAP_SIZE.x / 2))
    camera_position.y = clampf(camera_position.y, minf(half.y, MAP_SIZE.y / 2), maxf(MAP_SIZE.y - half.y, MAP_SIZE.y / 2))
    queue_redraw()

func pan_screen(delta: Vector2) -> void:
    camera_position -= delta / camera_zoom
    _refresh()

func zoom_at(factor: float, anchor: Vector2) -> void:
    var before := screen_to_world(anchor)
    camera_zoom = clampf(camera_zoom * factor, MIN_ZOOM, MAX_ZOOM)
    camera_position += before - screen_to_world(anchor)
    _refresh()

func _process(delta: float) -> void:
    if hold_pending and touches.size() == 1:
        hold_elapsed += delta
        if hold_elapsed >= HOLD_SECONDS:
            hold_pending = false
            touch_right = true
            _end_node_drag()
            context_pressed.emit(screen_to_world(hold_origin))
            queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        touches.clear()
        hold_pending = false
        touch_right = false
        mouse_right = false
        gesture_blocked = false
        _end_node_drag()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            if touches.is_empty():
                gesture_blocked = _over_ui(event.position)
            touches[event.index] = event.position
            hold_pending = touches.size() == 1 and not gesture_blocked
            hold_elapsed = 0.0
            hold_origin = event.position
            touch_right = false
            if touches.size() == 1 and not gesture_blocked:
                _begin_node_drag(event.position, true)
            else:
                _end_node_drag()
        else:
            touches.erase(event.index)
            _end_node_drag()
            hold_pending = false
            touch_right = false
            if touches.is_empty():
                gesture_blocked = false
        get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag:
        if not touches.has(event.index):
            return
        var previous: Vector2 = touches[event.index]
        if touches.size() == 2 and not gesture_blocked:
            var ids := touches.keys()
            var other: Vector2 = touches[ids[1] if ids[0] == event.index else ids[0]]
            var old_center := (previous + other) / 2.0
            var new_center: Vector2 = (event.position + other) / 2.0
            var old_distance := previous.distance_to(other)
            touches[event.index] = event.position
            pan_screen(new_center - old_center)
            if old_distance > 1.0:
                zoom_at(event.position.distance_to(other) / old_distance, new_center)
        else:
            touches[event.index] = event.position
            if touches.size() == 1 and not gesture_blocked:
                if touch_right:
                    pan_screen(event.position - previous)
                elif dragged_node >= 0 and drag_uses_touch:
                    if event.position.distance_to(hold_origin) > HOLD_SLOP:
                        node_drag_active = true
                        hold_pending = false
                    if node_drag_active:
                        _move_node(event.position)
                elif event.position.distance_to(hold_origin) > HOLD_SLOP:
                    hold_pending = false
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton:
        if event.device == InputEvent.DEVICE_ID_EMULATION:
            return
        if event.button_index == MOUSE_BUTTON_RIGHT:
            mouse_right = event.pressed and not _over_ui(event.position)
            if mouse_right:
                _end_node_drag()
                context_pressed.emit(screen_to_world(event.position))
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed and not mouse_right and touches.is_empty():
                _begin_node_drag(event.position, false)
            elif not event.pressed and not drag_uses_touch:
                _end_node_drag()
        elif event.pressed and not _over_ui(event.position):
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                zoom_at(1.12, event.position)
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                zoom_at(1.0 / 1.12, event.position)
    elif event is InputEventMouseMotion:
        if event.device != InputEvent.DEVICE_ID_EMULATION:
            if mouse_right:
                pan_screen(event.relative)
            elif dragged_node >= 0 and node_drag_active and not drag_uses_touch:
                _move_node(event.position)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("18241c"))
    draw_set_transform(size / 2.0 - camera_position * camera_zoom, 0, Vector2.ONE * camera_zoom)
    if grass:
        draw_texture_rect(grass, Rect2(Vector2.ZERO, MAP_SIZE), true)
    var visible := visible_world_rect().intersection(Rect2(Vector2.ZERO, MAP_SIZE))
    for x in range(int(ceil(visible.position.x / GRID)), int(floor(visible.end.x / GRID)) + 1):
        draw_line(Vector2(x * GRID, visible.position.y), Vector2(x * GRID, visible.end.y), Color(0.8, 0.9, 0.7, 0.14), 1.0 / camera_zoom)
    for y in range(int(ceil(visible.position.y / GRID)), int(floor(visible.end.y / GRID)) + 1):
        draw_line(Vector2(visible.position.x, y * GRID), Vector2(visible.end.x, y * GRID), Color(0.8, 0.9, 0.7, 0.14), 1.0 / camera_zoom)
    for i in range(node_positions.size()):
        var point := node_positions[i]
        if not visible.intersects(Rect2(point - NODE_HALF_SIZE - Vector2(6, 6), NODE_HALF_SIZE * 2 + Vector2(12, 12))):
            continue
        draw_style_box(node_style, Rect2(point - Vector2(65, 32), Vector2(130, 64)))
        if i == dragged_node:
            draw_rect(Rect2(point - NODE_HALF_SIZE, NODE_HALF_SIZE * 2), Color("e0f2b2"), false, 2.0 / camera_zoom)
        draw_circle(point + Vector2(-65, 0), 6, Color("8ee5cf"))
        draw_circle(point + Vector2(65, 0), 6, Color("8ee5cf"))
        draw_string(ThemeDB.fallback_font, point + Vector2(-40, 6), "NODE %02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2f1df"))
    draw_set_transform(Vector2.ZERO)
    draw_style_box(hud_style, Rect2(14, 14, minf(size.x - 28, 570), 116))
    draw_string(ThemeDB.fallback_font, Vector2(28, 40), "NodeNexus / NODE PROTOTYPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("d5efba"))
    draw_string(ThemeDB.fallback_font, Vector2(28, 65), "RMB drag: pan  /  Wheel: zoom", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
    draw_string(ThemeDB.fallback_font, Vector2(28, 89), "Touch: 2-finger pan / pinch / hold + drag", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
    draw_string(ThemeDB.fallback_font, Vector2(28, 113), "Node body: left drag / 1-finger drag", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
    var mini := minimap_rect()
    draw_style_box(minimap_style, mini.grow(5))
    draw_rect(mini, Color("3c5930"))
    var ratio := mini.size / MAP_SIZE
    for point in node_positions:
        draw_circle(mini.position + point * ratio, 3.5, Color("9df3d6"))
    var view := visible_world_rect().intersection(Rect2(Vector2.ZERO, MAP_SIZE))
    var frame := Rect2(mini.position + view.position * ratio, view.size * ratio)
    draw_rect(frame, Color(0.9, 1.0, 0.8, 0.12))
    draw_rect(frame, Color("e0f2b2"), false, 2)
    draw_string(ThemeDB.fallback_font, mini.position - Vector2(0, 12), "MAP  /  %d%%" % roundi(camera_zoom * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
    if touch_right:
        draw_circle(hold_origin, 18, Color("e0f2b2"), false, 2)

func _panel(color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(8)
    return style
