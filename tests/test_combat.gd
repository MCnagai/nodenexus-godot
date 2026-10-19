extends SceneTree

var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)

func screen(scene: Control, point: Vector2) -> Vector2:
    return scene.size / 2 + (point - scene.camera_position) * scene.camera_zoom

func click(scene: Control, point: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.position = point
    event.pressed = pressed
    scene._input(event)

func touch(scene: Control, point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
    var event := InputEventScreenTouch.new()
    event.position = point
    event.pressed = pressed
    event.index = index
    event.canceled = canceled
    scene._input(event)

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    scene.set_process(false)
    click(scene, scene.debug_button_rect(true).get_center(), true)
    click(scene, scene.debug_button_rect(true).get_center(), false)
    var ally: int = scene.node_positions.size() - 1
    touch(scene, scene.debug_button_rect(false).get_center(), true)
    touch(scene, scene.debug_button_rect(false).get_center(), false)
    var enemy: int = scene.node_positions.size() - 1
    var idle: int = scene.spawn_unit(true)
    check(scene.units[ally].hp == 10.0 and scene.units[enemy].hp == 8.0, "Debug buttons did not spawn correct HP")
    scene._tick_combat(1.25)
    check(scene.units[ally].hp == 10.0 and scene.units[enemy].hp == 8.0, "Unconnected unit lost HP")
    # Use world offsets independent of window size, with no HUD overlap.
    scene.node_positions[ally] = scene.camera_position + Vector2(-200, 100)
    scene.node_positions[enemy] = scene.camera_position + Vector2(200, 100)
    var output := screen(scene, scene.port_position(ally))
    var input := screen(scene, scene.port_position(enemy))
    click(scene, output, true)
    check(scene.wire_from == ally and scene.dragged_node == -1, "Output port moved unit instead of drawing wire")
    click(scene, Vector2(50, 500), false)
    check(scene.connections.is_empty() and scene.wire_from == -1, "Blank release created a connection")
    click(scene, output, true)
    click(scene, input, false)
    check(scene.connections.get(ally) == enemy, "Output to input did not connect")
    scene._tick_combat(0.25)
    check(is_equal_approx(scene.units[ally].hp, 9.75) and is_equal_approx(scene.units[enemy].hp, 7.75), "HP did not decay continuously at 1 per second")
    check(scene.units[idle].hp == 10.0, "Unconnected unit joined combat")
    check(scene.units[ally].hp_text() == "HP 9.8 / 10.0", "HP display is not one decimal")
    scene.units[ally].hp = 0.125
    scene.units[enemy].hp = 0.125
    scene._tick_combat(0.25)
    check(scene.units[ally].hp == 10.0 and scene.units[enemy].hp == 8.0, "Depleted HP did not reset to each maximum")
    # A duplicate link must not multiply the tick rate.
    click(scene, output, true)
    click(scene, input, false)
    scene._tick_combat(1.0)
    check(scene.units[ally].hp == 9.0 and scene.units[enemy].hp == 7.0, "Duplicate connection multiplied damage")
    scene.connections.clear()
    click(scene, output, true)
    click(scene, screen(scene, scene.port_position(idle)), false)
    check(scene.connections.is_empty(), "Same-side ports were connected")
    touch(scene, input, true)
    touch(scene, output, false)
    check(scene.connections.get(ally) == enemy, "Touch input-to-output drag was not normalized")
    click(scene, screen(scene, scene.port_position(idle)), true)
    click(scene, input, false)
    scene._tick_combat(1.0)
    check(scene.units[ally].hp == 8.0 and scene.units[enemy].hp == 6.0 and scene.units[idle].hp == 9.0, "Shared target multiplied HP decay")
    scene.connections.clear()
    touch(scene, output, true)
    touch(scene, input, false, 0, true)
    check(scene.connections.is_empty() and scene.wire_from == -1, "Canceled touch created a wire")
    touch(scene, output, true)
    touch(scene, input, true, 1)
    check(scene.wire_from == -1, "Second finger did not cancel wiring")
    touch(scene, input, false, 1)
    touch(scene, output, false)
    click(scene, output, true)
    scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(scene.wire_from == -1, "Focus loss did not cancel wiring")
    print("COMBAT_TEST_PASSED" if failures == 0 else "COMBAT_TEST_FAILED")
    quit(0 if failures == 0 else 1)
