extends SceneTree

var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)

func pointer(scene: Control, point: Vector2, phase: int, is_touch: bool = false, canceled: bool = false) -> void:
    var event: InputEvent
    if phase == 1:
        if is_touch:
            event = InputEventScreenDrag.new()
        else:
            event = InputEventMouseMotion.new()
    elif is_touch:
        event = InputEventScreenTouch.new()
        event.pressed = phase == 0
        event.canceled = canceled
    else:
        event = InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = phase == 0
    event.position = point
    scene._input(event)

func move_item(scene: Control, from: Vector2, to: Vector2, is_touch: bool = false, canceled: bool = false) -> void:
    pointer(scene, from, 0, is_touch)
    pointer(scene, to, 1, is_touch)
    pointer(scene, to, 2, is_touch, canceled)

func _run() -> void:
    root.size = Vector2i(1280, 720)
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    scene.set_process(false)
    var ally: int = scene.spawn_unit(true)
    var other: int = scene.spawn_unit(true)
    var enemy: int = scene.spawn_unit(false)
    scene.node_positions[ally] = scene.camera_position + Vector2(-180, -40)
    scene.node_positions[other] = scene.camera_position + Vector2(120, -40)
    scene.node_positions[enemy] = scene.camera_position + Vector2(360, -40)
    var body: Vector2 = scene.size / 2 + Vector2(-180, -40)
    var other_body: Vector2 = scene.size / 2 + Vector2(120, -40)
    var enemy_body: Vector2 = scene.size / 2 + Vector2(360, -40)
    var camera: Vector2 = scene.camera_position
    scene.inventory_open = true
    move_item(scene, scene.inventory_cell_rect(1).get_center(), scene.inventory_cell_rect(5).get_center())
    check(scene.item_store.cells[1].is_empty() and scene.item_store.cells[5].count == 2, "Inventory stack did not move")
    move_item(scene, scene.inventory_cell_rect(2).get_center(), scene.inventory_cell_rect(5).get_center(), true)
    check(scene.item_store.cells[2].kind == "sword" and scene.item_store.cells[5].kind == "herb", "Inventory stacks did not swap")
    move_item(scene, scene.inventory_cell_rect(2).get_center(), body, true)
    check(scene.units[ally].blocks == ["sword"] and scene.block_stock.sword == 1, "Touch drag did not equip exactly one sword")
    check(not scene.inventory_open, "Equip did not reveal the program")
    scene.inventory_open = true
    move_item(scene, scene.inventory_cell_rect(5).get_center(), body)
    check(scene.units[ally].blocks == ["sword", "herb"] and scene.block_stock.herb == 0, "Mouse drag did not append herb")
    move_item(scene, scene.block_rect(ally, 1).get_center(), scene.block_rect(ally, 0).get_center(), true)
    check(scene.units[ally].blocks == ["herb", "sword"], "Block reorder failed")
    move_item(scene, scene.block_rect(ally, 0).get_center(), other_body)
    check(scene.units[ally].blocks == ["sword"] and scene.units[other].blocks == ["herb"], "Cross-node move failed")
    move_item(scene, scene.block_rect(ally, 0).get_center(), scene.block_rect(other, 0).get_center(), true)
    check(scene.units[ally].blocks == ["herb"] and scene.units[other].blocks == ["sword"], "Cross-node swap failed")
    scene.inventory_open = true
    move_item(scene, scene.inventory_cell_rect(2).get_center(), scene.block_rect(ally, 0).get_center())
    check(scene.units[ally].blocks == ["sword"] and scene.block_stock.herb == 1 and scene.block_stock.sword == 0, "Inventory-to-block replacement lost items")
    move_item(scene, scene.block_rect(ally, 0).get_center(), scene.inventory_button_rect().get_center(), true)
    check(scene.units[ally].blocks.is_empty() and scene.block_stock.sword == 1 and scene.inventory_open, "Return via item-box button failed")
    # Place a returned item in a specific cell, then merge equal stacks.
    move_item(scene, scene.block_rect(other, 0).get_center(), scene.inventory_cell_rect(7).get_center())
    check(scene.units[other].blocks.is_empty() and scene.item_store.cells[7].count == 1, "Return to chosen cell failed")
    var sword_slot := -1
    for index in range(16):
        if index != 7 and scene.item_store.cells[index].get("kind", "") == "sword":
            sword_slot = index
    move_item(scene, scene.inventory_cell_rect(7).get_center(), scene.inventory_cell_rect(sword_slot).get_center())
    check(scene.item_store.cells[7].is_empty() and scene.block_stock.sword == 2, "Equal stacks did not merge")
    var before: Array = scene.item_store.cells.duplicate(true)
    move_item(scene, scene.inventory_cell_rect(sword_slot).get_center(), enemy_body, true)
    check(scene.item_store.cells == before and scene.units[enemy].blocks == ["sword"], "Enemy accepted equipment")
    move_item(scene, scene.inventory_cell_rect(sword_slot).get_center(), Vector2(600, 50))
    check(scene.item_store.cells == before, "Invalid drop lost stack")
    move_item(scene, scene.inventory_cell_rect(sword_slot).get_center(), body, true, true)
    check(scene.item_store.cells == before and scene.units[ally].blocks.is_empty(), "Canceled touch equipped an item")
    pointer(scene, scene.inventory_cell_rect(sword_slot).get_center(), 0, true)
    pointer(scene, body, 1, true)
    var second := InputEventScreenTouch.new()
    second.index = 1
    second.position = body + Vector2(100, 0)
    second.pressed = true
    scene._input(second)
    second.pressed = false
    scene._input(second)
    pointer(scene, body, 2, true)
    check(scene.item_store.cells == before and scene.units[ally].blocks.is_empty(), "Second finger committed a drag")
    scene.camera_position = camera
    pointer(scene, scene.inventory_cell_rect(sword_slot).get_center(), 0)
    pointer(scene, body, 1)
    scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    pointer(scene, body, 2)
    check(scene.item_source.is_empty() and scene.item_store.cells == before, "Focus loss committed a drag")
    # Moving a money stack must preserve where later pickups accumulate.
    check(scene.ItemStore.put(scene.item_store.cells, "money", 3), "Money fixture did not fit")
    var money_slot := -1
    for index in range(16):
        if scene.item_store.cells[index].get("kind", "") == "money":
            money_slot = index
    scene.inventory_open = true
    move_item(scene, scene.inventory_cell_rect(money_slot).get_center(), scene.inventory_cell_rect(15).get_center(), true)
    scene._drop_money(scene.node_positions[enemy])
    var drop: Vector2 = scene.size / 2 + (scene.drops.values()[0].position - scene.camera_position)
    pointer(scene, drop, 0)
    pointer(scene, drop, 2)
    check(scene.money_count == 4 and scene.item_store.cells[15].count == 4, "Pickup ignored moved money stack")
    # A full inventory must reject a replacement requiring another cell atomically.
    var store = load("res://scripts/item_store.gd").new()
    for index in range(16):
        store.cells[index] = {"kind": "money", "count": 1}
    store.cells[0] = {"kind": "sword", "count": 2}
    var snapshot: Array = store.cells.duplicate(true)
    check(store.plan({"cell": 0}, {"node": 0, "slot": 0}, {0: ["herb"]}).is_empty(), "Full inventory accepted an overflowing replacement")
    check(store.cells == snapshot, "Failed transaction mutated inventory")
    check(store.plan({"cell": 1}, {"node": 0, "slot": -1}, {0: []}).is_empty(), "Money became an action block")
    check(store.plan({"node": 0, "slot": 0}, {"cell": 1}, {0: ["herb"]}).is_empty(), "Action block replaced money")
    # Blocks must keep the same world proportions as their node at every zoom.
    scene.inventory_open = false
    scene.selected_block_node = -1
    scene.node_positions[ally] = scene.camera_position + Vector2(-100, -40)
    scene.camera_zoom = 1.0
    var base: Rect2 = scene.block_rect(ally, 0)
    var base_center: Vector2 = scene.size / 2 + (scene.node_positions[ally] - scene.camera_position)
    for zoom in [0.3, 1.0, 2.5]:
        scene.camera_zoom = zoom
        scene.units[ally].blocks.assign(["sword", "herb"])
        var rect: Rect2 = scene.block_rect(ally, 0)
        var node_center: Vector2 = scene.size / 2 + (scene.node_positions[ally] - scene.camera_position) * zoom
        check(rect.size.is_equal_approx(base.size * zoom), "Block size did not follow node zoom")
        check((rect.position - node_center).is_equal_approx((base.position - base_center) * zoom), "Block offset detached from node during zoom")
        check(is_equal_approx(rect.size.x, scene.NODE_HALF_SIZE.x * 2 * zoom), "Block width no longer matches node")
        check(scene._item_target(rect.get_center()).get("slot", -1) == 0, "Drop hit region disagrees with zoomed block")
        move_item(scene, scene.block_rect(ally, 1).get_center(), rect.get_center(), true)
        check(scene.units[ally].blocks == ["herb", "sword"], "Touch reorder failed at changed zoom")
    print("ITEM_DRAG_TEST_PASSED" if failures == 0 else "ITEM_DRAG_TEST_FAILED")
    quit(0 if failures == 0 else 1)
