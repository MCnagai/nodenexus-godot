extends Control

const DebugUnit = preload("res://scripts/debug_unit.gd")

signal context_pressed(world_position: Vector2)

const MAP_SIZE := Vector2(6000, 6000)
const GRID := 100.0
const MIN_ZOOM := 0.3
const MAX_ZOOM := 2.5
const HOLD_SECONDS := 0.5
const HOLD_SLOP := 12.0
const NODE_HALF_SIZE := Vector2(80, 38)
const PORT_HIT_RADIUS := 12.0

var camera_position := MAP_SIZE / 2.0
var camera_zoom := 1.0
# The board starts empty; debug units are created through the menu.
var node_positions: Array[Vector2] = []
var units: Dictionary = {}
# One connection per debug output; replacing a connection changes its target.
var connections: Dictionary = {}
var wire_from := -1
var wire_pointer := Vector2.ZERO
var wire_press_position := Vector2.ZERO
var wire_dragged := false
var wire_uses_touch := false
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
var hovered_node := -1
var mouse_present := false
var mouse_position := Vector2.ZERO
var dragged_node := -1
var drag_offset := Vector2.ZERO
var node_drag_active := false
var drag_uses_touch := false

func _ready() -> void:
    _configure_canvas()
    get_window().size_changed.connect(_configure_canvas)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    grass = _make_grass()
    node_style = _panel(Color("233b37"))
    hud_style = _panel(Color(0.06, 0.12, 0.10, 0.92))
    minimap_style = _panel(Color("122b23"))
    resized.connect(_refresh)
    get_window().mouse_exited.connect(_clear_hover)
    _refresh()

func _configure_canvas() -> void:
    var window := get_window()
    var reference := Vector2i(480, 320) if window.size.y < 500 and window.size.x > window.size.y else Vector2i(480, 720)
    if window.content_scale_size != reference:
        window.content_scale_size = reference

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

func debug_ui_scale() -> float:
    return clampf(size.x / maxf(1.0, get_window().size.x), 1.0, 3.0)

func hud_rect() -> Rect2:
    var scale := debug_ui_scale()
    if get_window().size.x < 700 or get_window().size.y < 500:
        return Rect2(Vector2(14, 14) * scale, Vector2(minf(198 * scale, maxf(80, debug_menu_rect().position.x - 28 * scale)), 136 * scale))
    return Rect2(14, 14, minf(size.x - 28, 570), 140)

func debug_menu_rect() -> Rect2:
    var scale := debug_ui_scale()
    return Rect2(Vector2(size.x - 214 * scale, 14 * scale), Vector2(200, 152) * scale)

func debug_button_rect(friendly: bool) -> Rect2:
    var menu := debug_menu_rect()
    var scale := debug_ui_scale()
    return Rect2(menu.position + Vector2(12, 36 if friendly else 94) * scale, Vector2(176, 44) * scale)

func _debug_ui_press(point: Vector2) -> void:
    if debug_button_rect(true).has_point(point):
        spawn_unit(true)
    elif debug_button_rect(false).has_point(point):
        spawn_unit(false)

func spawn_unit(friendly: bool) -> int:
    var index := node_positions.size()
    var side := -1.0 if friendly else 1.0
    var count := 0
    for unit in units.values():
        if unit.friendly == friendly:
            count += 1
    var horizontal := minf(170.0, maxf(0.0, size.x / 2 - NODE_HALF_SIZE.x - 24) * 0.8)
    var vertical := minf(140.0 + (count % 4) * 100, maxf(0.0, size.y / 2 - NODE_HALF_SIZE.y - 24))
    var offset := Vector2(side * horizontal, vertical) / camera_zoom
    var screen_center := size / 2 + offset * camera_zoom
    var body := Rect2(screen_center - NODE_HALF_SIZE * camera_zoom, NODE_HALF_SIZE * 2 * camera_zoom)
    if not friendly and body.intersects(minimap_rect().grow(12)):
        screen_center.x = minf(screen_center.x, minimap_rect().position.x - NODE_HALF_SIZE.x * camera_zoom - 16)
    var point := screen_to_world(screen_center).clamp(NODE_HALF_SIZE, MAP_SIZE - NODE_HALF_SIZE)
    node_positions.append(point)
    units[index] = DebugUnit.new(friendly)
    queue_redraw()
    return index

func port_position(index: int) -> Vector2:
    var side := 1.0 if units[index].friendly else -1.0
    return node_positions[index] + Vector2(side * NODE_HALF_SIZE.x, 0)

func _pick_port(point: Vector2) -> int:
    if _over_ui(point):
        return -1
    var world := screen_to_world(point)
    for index in range(node_positions.size() - 1, -1, -1):
        if units.has(index) and world.distance_to(port_position(index)) <= maxf(PORT_HIT_RADIUS, 14.0 * debug_ui_scale() / camera_zoom):
            return index
    return -1

func _begin_wire(point: Vector2, from_touch: bool) -> bool:
    var index := _pick_port(point)
    if index == -1:
        return false
    wire_from = index
    wire_pointer = point
    wire_press_position = point
    wire_dragged = false
    wire_uses_touch = from_touch
    hold_pending = false
    _end_node_drag()
    queue_redraw()
    return true

func _update_wire_pointer(point: Vector2) -> void:
    wire_pointer = point
    # Logical canvas units -> CSS pixels; small touch jitter is still a tap.
    var css_scale := get_viewport().get_stretch_transform().get_scale().x
    if point.distance_to(wire_press_position) * css_scale > 8.0:
        wire_dragged = true
    queue_redraw()

func _disconnect_port(index: int) -> void:
    if units[index].friendly:
        connections.erase(index)
    else:
        for source in connections.keys():
            if connections[source] == index:
                connections.erase(source)
    queue_redraw()

func _cancel_wire() -> void:
    if wire_from != -1:
        wire_from = -1
        queue_redraw()

func _finish_wire(point: Vector2) -> void:
    if wire_from == -1:
        return
    var target := _pick_port(point)
    _update_wire_pointer(point)
    if target == wire_from and not wire_dragged:
        _disconnect_port(wire_from)
    elif target != -1 and units[wire_from].friendly != units[target].friendly:
        var source: int = wire_from if units[wire_from].friendly else target
        var destination: int = target if units[wire_from].friendly else wire_from
        connections[source] = destination
    _cancel_wire()

func _tick_combat(delta: float) -> void:
    var active: Dictionary = {}
    for source in connections:
        active[source] = true
        active[connections[source]] = true
    for index in active:
        units[index].tick(delta)
    if not active.is_empty():
        queue_redraw()

func _draw_wire(source: Vector2, target: Vector2, color: Color) -> void:
    var bend := maxf(50.0, absf(target.x - source.x) * 0.5)
    var curve := Curve2D.new()
    curve.add_point(source, Vector2.ZERO, Vector2(bend, 0))
    curve.add_point(target, Vector2(-bend, 0))
    draw_polyline(curve.get_baked_points(), color, 2.5 * debug_ui_scale() / camera_zoom, true)

func _over_ui(point: Vector2) -> bool:
    return debug_menu_rect().has_point(point) or minimap_rect().grow(5).has_point(point) or hud_rect().has_point(point)

func _pick_node(screen_point: Vector2) -> int:
    var point := screen_to_world(screen_point)
    # Last drawn node wins when bodies overlap. Ports are reserved for wiring.
    for i in range(node_positions.size() - 1, -1, -1):
        var center := node_positions[i]
        if Rect2(center - NODE_HALF_SIZE, NODE_HALF_SIZE * 2).has_point(point):
            if units.has(i):
                if point.distance_to(port_position(i)) <= PORT_HIT_RADIUS:
                    return -1
            else:
                for side in [-1, 1]:
                    if point.distance_to(center + Vector2(side * NODE_HALF_SIZE.x, 0)) <= PORT_HIT_RADIUS:
                        return -1
            return i
    return -1

func _clear_hover() -> void:
    mouse_present = false
    if hovered_node != -1:
        hovered_node = -1
        queue_redraw()

func _update_hover() -> void:
    var next := -1
    if mouse_present and touches.is_empty() and dragged_node == -1 and wire_from == -1 and not mouse_right and not _over_ui(mouse_position):
        next = _pick_node(mouse_position)
    if next != hovered_node:
        hovered_node = next
        queue_redraw()

func _begin_node_drag(point: Vector2, from_touch: bool) -> void:
    if _over_ui(point):
        return
    dragged_node = _pick_node(point)
    if dragged_node >= 0:
        drag_offset = node_positions[dragged_node] - screen_to_world(point)
        drag_uses_touch = from_touch
        node_drag_active = not from_touch
        _update_hover()
        queue_redraw()

func _end_node_drag() -> void:
    dragged_node = -1
    node_drag_active = false
    _update_hover()
    queue_redraw()

func _move_node(point: Vector2) -> void:
    var target := screen_to_world(point) + drag_offset
    node_positions[dragged_node] = target.clamp(NODE_HALF_SIZE, MAP_SIZE - NODE_HALF_SIZE)
    queue_redraw()

func _refresh() -> void:
    var half := size / camera_zoom / 2.0
    camera_position.x = clampf(camera_position.x, minf(half.x, MAP_SIZE.x / 2), maxf(MAP_SIZE.x - half.x, MAP_SIZE.x / 2))
    camera_position.y = clampf(camera_position.y, minf(half.y, MAP_SIZE.y / 2), maxf(MAP_SIZE.y - half.y, MAP_SIZE.y / 2))
    _update_hover()
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
    _tick_combat(delta)
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
        _clear_hover()
        _cancel_wire()
        touches.clear()
        hold_pending = false
        touch_right = false
        mouse_right = false
        gesture_blocked = false
        _end_node_drag()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        _clear_hover()
        if event.pressed:
            if touches.is_empty():
                gesture_blocked = _over_ui(event.position)
            touches[event.index] = event.position
            hold_pending = touches.size() == 1 and not gesture_blocked
            hold_elapsed = 0.0
            hold_origin = event.position
            touch_right = false
            if touches.size() == 1:
                if gesture_blocked:
                    _debug_ui_press(event.position)
                elif not _begin_wire(event.position, true):
                    _begin_node_drag(event.position, true)
            else:
                _cancel_wire()
                _end_node_drag()
        else:
            if not event.canceled and wire_uses_touch:
                _finish_wire(event.position)
            else:
                _cancel_wire()
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
                if wire_from != -1 and wire_uses_touch:
                    _update_wire_pointer(event.position)
                elif touch_right:
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
        mouse_present = true
        mouse_position = event.position
        if event.button_index == MOUSE_BUTTON_RIGHT:
            mouse_right = event.pressed and not _over_ui(event.position)
            if mouse_right:
                _cancel_wire()
                _end_node_drag()
                context_pressed.emit(screen_to_world(event.position))
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed and not mouse_right and touches.is_empty():
                if _over_ui(event.position):
                    _debug_ui_press(event.position)
                elif not _begin_wire(event.position, false):
                    _begin_node_drag(event.position, false)
            elif not event.pressed and not wire_uses_touch:
                _finish_wire(event.position)
                _end_node_drag()
            elif not event.pressed and not drag_uses_touch:
                _end_node_drag()
        elif event.pressed and not _over_ui(event.position):
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                zoom_at(1.12, event.position)
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                zoom_at(1.0 / 1.12, event.position)
        _update_hover()
    elif event is InputEventMouseMotion:
        if event.device != InputEvent.DEVICE_ID_EMULATION:
            mouse_present = true
            mouse_position = event.position
            if mouse_right:
                pan_screen(event.relative)
            elif wire_from != -1 and not wire_uses_touch:
                _update_wire_pointer(event.position)
            elif dragged_node >= 0 and node_drag_active and not drag_uses_touch:
                _move_node(event.position)
            _update_hover()

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
    for source in connections:
        _draw_wire(port_position(source), port_position(connections[source]), Color("e0f2b2"))
    if wire_from != -1:
        var endpoint := screen_to_world(wire_pointer)
        if units[wire_from].friendly:
            _draw_wire(port_position(wire_from), endpoint, Color("8ee5cf"))
        else:
            _draw_wire(endpoint, port_position(wire_from), Color("8ee5cf"))
    for i in range(node_positions.size()):
        var point := node_positions[i]
        if not visible.intersects(Rect2(point - NODE_HALF_SIZE - Vector2(6, 6), NODE_HALF_SIZE * 2 + Vector2(12, 12))):
            continue
        draw_style_box(node_style, Rect2(point - NODE_HALF_SIZE, NODE_HALF_SIZE * 2))
        if i == hovered_node:
            draw_rect(Rect2(point - NODE_HALF_SIZE, NODE_HALF_SIZE * 2), Color("8ee5cf"), false, 2.0 / camera_zoom)
        if i == dragged_node:
            draw_rect(Rect2(point - NODE_HALF_SIZE, NODE_HALF_SIZE * 2), Color("e0f2b2"), false, 2.0 / camera_zoom)
        if units.has(i):
            var unit = units[i]
            var color := Color("8ee5cf") if unit.friendly else Color("f29b94")
            draw_circle(port_position(i), 7.0 * debug_ui_scale() / camera_zoom, color)
            draw_string(ThemeDB.fallback_font, point + Vector2(-68, -12), "ALLY / OUT" if unit.friendly else "ENEMY / IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
            draw_string(ThemeDB.fallback_font, point + Vector2(-68, 14), unit.hp_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
            draw_rect(Rect2(point + Vector2(-68, 26), Vector2(136, 4)), Color("152a25"))
            draw_rect(Rect2(point + Vector2(-68, 26), Vector2(136 * unit.hp / unit.max_hp, 4)), color)
        else:
            draw_circle(point + Vector2(-NODE_HALF_SIZE.x, 0), 6, Color("8ee5cf"))
            draw_circle(point + Vector2(NODE_HALF_SIZE.x, 0), 6, Color("8ee5cf"))
            draw_string(ThemeDB.fallback_font, point + Vector2(-40, 6), "NODE %02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2f1df"))
    draw_set_transform(Vector2.ZERO)
    var hud := hud_rect()
    draw_style_box(hud_style, hud)
    if get_window().size.x < 700 or get_window().size.y < 500:
        var scale := debug_ui_scale()
        draw_string(ThemeDB.fallback_font, hud.position + Vector2(10, 22) * scale, "NodeNexus", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * scale), Color("d5efba"))
        var hints := ["Node drag: move", "2 fingers: pan", "Pinch: zoom", "Port drag: connect", "Port tap: unlink"]
        for line in range(hints.size()):
            draw_string(ThemeDB.fallback_font, hud.position + Vector2(10, 42 + line * 20) * scale, hints[line], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12 * scale))
    else:
        draw_string(ThemeDB.fallback_font, Vector2(28, 40), "NodeNexus / NODE PROTOTYPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("d5efba"))
        draw_string(ThemeDB.fallback_font, Vector2(28, 65), "RMB drag: pan  /  Wheel: zoom", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
        draw_string(ThemeDB.fallback_font, Vector2(28, 89), "Touch: 2-finger pan / pinch / hold + drag", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
        draw_string(ThemeDB.fallback_font, Vector2(28, 113), "Node body: left drag / 1-finger drag", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
        draw_string(ThemeDB.fallback_font, Vector2(28, 137), "Port: drag to connect / tap to disconnect", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
    var menu := debug_menu_rect()
    var ui_scale := debug_ui_scale()
    draw_style_box(hud_style, menu)
    draw_string(ThemeDB.fallback_font, menu.position + Vector2(12, 23) * ui_scale, "DEBUG / UNITS", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * ui_scale))
    for friendly in [true, false]:
        var button := debug_button_rect(friendly)
        draw_style_box(node_style, button)
        draw_string(ThemeDB.fallback_font, button.position + Vector2(10, 28) * ui_scale, "+ ALLY  HP 10" if friendly else "+ ENEMY  HP 8", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * ui_scale), Color("8ee5cf") if friendly else Color("f29b94"))
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
    draw_string(ThemeDB.fallback_font, mini.position - Vector2(0, 12), "MAP  /  %d%%" % roundi(camera_zoom * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * debug_ui_scale()))
    if touch_right:
        draw_circle(hold_origin, 18, Color("e0f2b2"), false, 2)

func _panel(color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(8)
    return style
