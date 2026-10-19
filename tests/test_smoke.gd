extends SceneTree

var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func check(condition: bool, message: String) -> void:
    if not condition:
        push_error(message)
        failures += 1

func touch(scene: Control, index: int, position: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = position
    event.pressed = pressed
    scene._input(event)

func drag(scene: Control, index: int, position: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = position
    scene._input(event)

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    check(scene.grass != null, "Grass texture missing")
    var start: Vector2 = scene.camera_position
    var button := InputEventMouseButton.new()
    button.button_index = MOUSE_BUTTON_RIGHT
    button.position = Vector2(300, 200)
    button.pressed = true
    scene._input(button)
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(100, 50)
    scene._input(motion)
    check(scene.camera_position.is_equal_approx(start - motion.relative), "RMB pan failed")
    button.pressed = false
    scene._input(button)
    var anchor := Vector2(250, 250)
    var world: Vector2 = scene.screen_to_world(anchor)
    button.button_index = MOUSE_BUTTON_WHEEL_UP
    button.position = anchor
    button.pressed = true
    scene._input(button)
    check(is_equal_approx(scene.camera_zoom, 1.12), "Wheel zoom failed")
    check(scene.screen_to_world(anchor).is_equal_approx(world), "Zoom anchor drifted")
    scene.camera_zoom = 1.0
    scene.camera_position = start
    touch(scene, 0, Vector2(300, 300), true)
    scene._process(0.6)
    check(scene.touch_right, "Long press did not become RMB")
    drag(scene, 0, Vector2(350, 300))
    check(scene.camera_position.is_equal_approx(start - Vector2(50, 0)), "Hold drag failed")
    touch(scene, 0, Vector2(350, 300), false)
    touch(scene, 0, Vector2(300, 300), true)
    drag(scene, 0, Vector2(330, 300))
    scene._process(0.6)
    check(not scene.touch_right, "Moving finger triggered hold")
    touch(scene, 1, Vector2(500, 300), true)
    var before: Vector2 = scene.screen_to_world(Vector2(415, 300))
    drag(scene, 1, Vector2(600, 300))
    check(scene.camera_zoom > 1.0, "Pinch zoom failed")
    check(scene.screen_to_world(Vector2(465, 300)).is_equal_approx(before), "Pinch centroid anchor drifted")
    touch(scene, 1, Vector2(600, 300), false)
    scene._process(0.6)
    check(not scene.touch_right, "Remaining finger triggered accidental hold")
    scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(scene.touches.is_empty() and not scene.mouse_right, "Focus loss left input active")
    # Drag in world coordinates at a non-default zoom, preserving grab offset.
    scene.camera_position = start
    scene.camera_zoom = 2.0
    var node_start: Vector2 = scene.node_positions[0]
    var grab: Vector2 = scene.size / 2 + Vector2(20, 10)
    button.button_index = MOUSE_BUTTON_LEFT
    button.position = grab
    button.pressed = true
    scene._input(button)
    motion.position = grab + Vector2(160, 80)
    scene._input(motion)
    check(scene.node_positions[0].is_equal_approx(node_start + Vector2(80, 40)), "Mouse node drag lost zoom/offset")
    check(scene.camera_position.is_equal_approx(start), "Node drag moved camera")
    button.pressed = false
    scene._input(button)
    var released: Vector2 = scene.node_positions[0]
    motion.position += Vector2(100, 0)
    scene._input(motion)
    check(scene.node_positions[0] == released and scene.dragged_node == -1, "Node kept following after release")
    scene.node_positions[0] = node_start
    scene.camera_zoom = 1.0
    button.position = scene.size / 2 + Vector2(64, 0)
    button.pressed = true
    scene._input(button)
    check(scene.dragged_node == -1, "Port started body drag")
    button.pressed = false
    scene._input(button)
    var center: Vector2 = scene.size / 2
    touch(scene, 0, center, true)
    drag(scene, 0, center + Vector2(5, 0))
    check(scene.node_positions[0] == node_start, "Touch jitter moved node")
    drag(scene, 0, center + Vector2(80, 40))
    check(scene.node_positions[0].is_equal_approx(node_start + Vector2(80, 40)), "Single-finger node drag failed")
    scene._process(0.6)
    check(not scene.touch_right, "Node drag became long press")
    touch(scene, 1, center + Vector2(200, 0), true)
    check(scene.dragged_node == -1, "Second finger did not cancel node drag")
    var two_finger_node: Vector2 = scene.node_positions[0]
    drag(scene, 1, center + Vector2(240, 0))
    touch(scene, 1, center + Vector2(240, 0), false)
    drag(scene, 0, center + Vector2(100, 50))
    check(scene.node_positions[0] == two_finger_node, "Node moved during/after two-finger gesture")
    touch(scene, 0, center + Vector2(100, 50), false)
    scene.camera_position = start
    scene.camera_zoom = 1.0
    scene.node_positions[0] = node_start
    touch(scene, 0, center, true)
    scene._process(0.6)
    check(scene.touch_right and scene.dragged_node == -1, "Hold on node did not switch to RMB")
    drag(scene, 0, center + Vector2(80, 0))
    check(scene.node_positions[0] == node_start, "Hold camera gesture moved node")
    scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(scene.dragged_node == -1, "Focus loss did not cancel node drag")
    scene.camera_position = start
    button.position = center
    button.pressed = true
    scene._input(button)
    motion.position = Vector2(-100000, -100000)
    scene._input(motion)
    check(scene.node_positions[0] == scene.NODE_HALF_SIZE, "Node escaped map bounds")
    button.pressed = false
    scene._input(button)
    scene.zoom_at(10000.0, scene.size / 2)
    check(is_equal_approx(scene.camera_zoom, scene.MAX_ZOOM), "Maximum zoom failed")
    scene.zoom_at(0.00001, scene.size / 2)
    check(is_equal_approx(scene.camera_zoom, scene.MIN_ZOOM), "Minimum zoom failed")
    scene.pan_screen(Vector2(100000, 100000))
    check(scene.visible_world_rect().position.x >= -0.01, "Camera escaped map bounds")
    print("SMOKE_TEST_PASSED" if failures == 0 else "SMOKE_TEST_FAILED")
    quit(0 if failures == 0 else 1)
