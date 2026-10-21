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

func reset_pair(scene: Control, ally: int, enemy: int) -> void:
    scene.connections.clear()
    scene._tick_combat(0)
    scene.units[ally].hp = 10.0
    scene.units[enemy].hp = 8.0
    scene.connections[ally] = enemy

func _run() -> void:
    root.size = Vector2i(1280, 720)
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    scene.set_process(false)
    click(scene, scene.debug_button_rect(true).get_center(), true)
    click(scene, scene.debug_button_rect(true).get_center(), false)
    touch(scene, scene.debug_button_rect(false).get_center(), true)
    touch(scene, scene.debug_button_rect(false).get_center(), false)
    var ally := 0
    var enemy := 1
    scene.node_positions[ally] = scene.camera_position + Vector2(-200, 0)
    scene.node_positions[enemy] = scene.camera_position + Vector2(200, 0)
    var output := screen(scene, scene.port_position(ally))
    var input := screen(scene, scene.port_position(enemy))
    check(scene.units[ally].blocks.is_empty(), "Ally must start without blocks")
    check(scene.units[enemy].blocks == ["sword"], "Enemy must have a fixed attack block")
    check(scene.block_stock == {"sword": 2, "herb": 1}, "Initial sword/herb stock missing")
    scene._tick_combat(2)
    check(scene.units[ally].hp == 10 and scene.units[enemy].hp == 8, "Idle units executed")
    click(scene, output, true)
    click(scene, Vector2(600, 600), false)
    check(scene.connections.is_empty(), "Blank release connected")
    click(scene, output, true)
    click(scene, input, false)
    scene._tick_combat(0.5)
    check(scene.units[ally].hp == 10 and scene.units[enemy].hp == 8, "Block fired before one second")
    scene._tick_combat(0.5)
    check(scene.units[ally].hp == 8 and scene.units[enemy].hp == 8, "Empty ally attacked or enemy attack was not 2")
    click(scene, output, true)
    click(scene, output, false)
    check(scene.connections.is_empty(), "Output tap failed to unlink")
    scene._tick_combat(2)
    check(scene.units[ally].hp == 8, "Disconnected enemy attacked")
    # Touch stock selection, then a separate release-validated equip tap.
    touch(scene, scene.inventory_button_rect().get_center(), true)
    touch(scene, scene.inventory_button_rect().get_center(), false)
    touch(scene, scene.inventory_cell_rect(1).get_center(), true)
    touch(scene, scene.inventory_cell_rect(1).get_center(), false)
    check(scene.pending_item == "sword" and not scene.inventory_open, "Selecting sword did not enter equip mode")
    var body := screen(scene, scene.node_positions[ally])
    touch(scene, body, true)
    touch(scene, body, false, 0, true)
    check(scene.units[ally].blocks.is_empty() and scene.block_stock.sword == 2, "Canceled equip consumed stock")
    touch(scene, body, true)
    touch(scene, body + Vector2(100, 0), true, 1)
    touch(scene, body + Vector2(100, 0), false, 1)
    touch(scene, body, false)
    check(scene.units[ally].blocks.is_empty(), "Two-finger equip consumed stock")
    touch(scene, body, true)
    touch(scene, body, false)
    check(scene.units[ally].blocks == ["sword"] and scene.block_stock.sword == 1, "Touch equip did not transfer sword")
    check(scene.equip_block(ally, "herb"), "Herb equip failed")
    check(not scene.equip_block(ally, "herb"), "Empty stock duplicated herb")
    check(not scene.equip_block(enemy, "sword"), "Enemy loadout was editable")
    # Select and reorder the visible herb row, then remove and return it.
    var herb: Vector2 = scene.block_rect(ally, 1).get_center()
    click(scene, herb, true)
    click(scene, herb, false)
    click(scene, scene.block_action_rect(0).get_center(), true)
    click(scene, scene.block_action_rect(0).get_center(), false)
    check(scene.units[ally].blocks == ["herb", "sword"], "UP did not reorder")
    scene.edit_block(1)
    check(scene.units[ally].blocks == ["sword", "herb"], "DOWN did not reorder")
    scene.edit_block(0)
    check(scene.units[ally].blocks == ["sword"] and scene.block_stock.herb == 1, "Remove lost/duplicated herb")
    scene.equip_block(ally, "herb")
    reset_pair(scene, ally, enemy)
    scene.units[ally].hp = 6
    scene._tick_combat(1)
    check(scene.units[ally].hp == 4 and scene.units[enemy].hp == 6, "First sword did not execute")
    scene._tick_combat(1)
    check(scene.units[ally].hp == 3 and scene.units[enemy].hp == 6, "Second herb did not heal 1")
    check(scene.units[ally].last_block == 1 and scene.units[ally].next_block == 0, "Program did not wrap")
    scene.units[ally].heal(100)
    check(scene.units[ally].hp == 10, "Healing exceeded max HP")
    # The next row fills clockwise from top center, independently of the flash.
    var border := Rect2(10, 20, 160, 40)
    check(scene.block_border_points(border, 0) == PackedVector2Array([Vector2(90, 20)]), "Clock border must start at top center")
    check(scene.block_border_points(border, 0.2)[-1].is_equal_approx(Vector2(170, 20)), "Clock border did not fill top-right first")
    check(scene.block_border_points(border, 0.5)[-1].is_equal_approx(Vector2(90, 60)), "Half progress must reach bottom center")
    check(scene.block_border_points(border, 1)[-1].is_equal_approx(Vector2(90, 20)), "Full progress did not close clockwise loop")
    reset_pair(scene, ally, enemy)
    scene._tick_combat(0.5)
    check(scene.units[ally].next_block == 0 and is_equal_approx(scene.units[ally].elapsed, 0.5), "Progress detached from action timer")
    check(scene.units[ally].last_block == -1 and scene.units[ally].flash_remaining == 0, "Flash occurred before execution")
    scene._tick_combat(0.5)
    check(scene.units[ally].next_block == 1 and scene.units[ally].last_block == 0 and scene.units[ally].flash_remaining > 0, "Execution did not move progress to next row and flash previous row")
    scene._tick_combat(0.2)
    check(scene.units[ally].flash_remaining == 0 and is_equal_approx(scene.units[ally].elapsed, 0.2), "Flash did not fade while next row progressed")
    scene.connections.clear()
    scene._tick_combat(0)
    check(scene.units[ally].elapsed == 0 and scene.units[ally].flash_remaining == 0 and scene.units[ally].next_block == 0, "Unlink did not reset progress/flash")
    # A slow frame must execute the same chronological steps as short frames.
    reset_pair(scene, ally, enemy)
    scene._tick_combat(3.25)
    var large_hp: float = scene.units[ally].hp
    var enemy_hp: float = scene.units[enemy].hp
    reset_pair(scene, ally, enemy)
    for step in range(13):
        scene._tick_combat(0.25)
    check(scene.units[ally].hp == large_hp and scene.units[enemy].hp == enemy_hp, "Frame size changed execution order")
    # A fresh connection waits a full second; port tap/cancel still work.
    touch(scene, input, true)
    touch(scene, input + Vector2(1, 0), false)
    check(scene.connections.is_empty(), "Input tap did not unlink")
    touch(scene, input, true)
    touch(scene, output, false)
    scene.units[enemy].hp = 8
    scene._tick_combat(0.99)
    check(scene.units[enemy].hp == 8, "Reconnect retained old timer")
    scene._tick_combat(0.01)
    check(scene.units[enemy].hp == 6, "Reconnect did not begin at top")
    touch(scene, output, true)
    touch(scene, output, false, 0, true)
    check(scene.connections.has(ally), "Canceled port tap disconnected")
    click(scene, output, true)
    scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
    check(scene.wire_from == -1 and not scene.action_pending, "Focus loss left an action active")
    # Defeat and collectible currency still work, once per enemy defeat.
    reset_pair(scene, ally, enemy)
    scene.units[enemy].hp = 2
    scene.drops.clear()
    scene._tick_combat(1)
    check(scene.units[enemy].hp == 8 and scene.drops.size() == 1, "Enemy defeat/reset/drop failed")
    var idle: int = scene.spawn_unit(true)
    scene.connections[idle] = enemy
    scene.units[enemy].hp = 2
    scene.units[ally].reset_program()
    scene._tick_combat(1)
    check(scene.drops.values()[0].amount == 2, "Repeated/shared enemy defeat duplicated or lost drop")
    scene.connections.clear()
    click(scene, output, true)
    click(scene, screen(scene, scene.port_position(idle)), false)
    check(scene.connections.is_empty(), "Same-side ports connected")
    touch(scene, output, true)
    touch(scene, input, true, 1)
    check(scene.wire_from == -1, "Second finger did not cancel wire")
    touch(scene, input, false, 1)
    touch(scene, output, false)
    check(scene.connections.is_empty(), "Canceled wire created a link")
    var coin := screen(scene, scene.drops.values()[0].position)
    touch(scene, coin, true)
    touch(scene, coin, false, 0, true)
    check(scene.money_count == 0, "Canceled pickup collected money")
    touch(scene, coin, true)
    touch(scene, coin + Vector2(50, 0), true, 1)
    touch(scene, coin + Vector2(50, 0), false, 1)
    touch(scene, coin, false)
    check(scene.money_count == 0, "Two-finger gesture collected money")
    click(scene, coin, true)
    var motion := InputEventMouseMotion.new()
    motion.position = coin + Vector2(50, 0)
    scene._input(motion)
    motion.position = coin
    scene._input(motion)
    click(scene, coin, false)
    check(scene.money_count == 0, "Drag-return collected money")
    click(scene, coin, true)
    click(scene, coin, false)
    check(scene.money_count == 2 and scene.drops.is_empty(), "Mouse pickup did not collect stack")
    scene._drop_money(scene.node_positions[enemy])
    touch(scene, coin, true)
    touch(scene, coin, false)
    check(scene.money_count == 3, "Touch pickup failed")
    for cell in range(16):
        check(scene.inventory_rect().encloses(scene.inventory_cell_rect(cell)), "Cell outside inventory")
    # Pickup bounds use the same world coordinates as the zoomed drop icon.
    for zoom in [0.3, 1.0, 2.5]:
        scene.camera_zoom = zoom
        scene.drops.clear()
        scene._drop_money(scene.camera_position)
        var center: Vector2 = screen(scene, scene.drops.values()[0].position)
        var id: int = scene.drops.keys()[0]
        check(scene._pick_drop(center + Vector2(23.9 * zoom, 0)) == id, "Zoomed drop lost its inner pickup edge")
        check(scene._pick_drop(center + Vector2(24.1 * zoom, 0)) == -1, "Drop pickup radius stayed in screen pixels")
        var before: int = scene.money_count
        click(scene, center, true)
        click(scene, center, false)
        check(scene.money_count == before + 1 and scene.drops.is_empty(), "Mouse pickup failed at changed zoom")
        scene._drop_money(scene.camera_position)
        touch(scene, center, true)
        touch(scene, center, false)
        check(scene.money_count == before + 2 and scene.drops.is_empty(), "Touch pickup failed at changed zoom")
    print("COMBAT_TEST_PASSED" if failures == 0 else "COMBAT_TEST_FAILED")
    quit(0 if failures == 0 else 1)
