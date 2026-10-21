extends RefCounted

var cells: Array[Dictionary] = []

func _init() -> void:
    for index in range(16):
        cells.append({})
    cells[1] = {"kind": "sword", "count": 2}
    cells[2] = {"kind": "herb", "count": 1}

func total(kind: String) -> int:
    var result := 0
    for cell in cells:
        if cell.get("kind", "") == kind:
            result += int(cell.count)
    return result

static func put(items: Array[Dictionary], kind: String, count: int, preferred: int = -1) -> bool:
    if preferred >= 0:
        if not items[preferred].is_empty() and items[preferred].kind != kind:
            return false
        items[preferred] = {"kind": kind, "count": int(items[preferred].get("count", 0)) + count}
        return true
    for index in range(items.size()):
        if items[index].get("kind", "") == kind:
            return put(items, kind, count, index)
    for index in range(items.size()):
        if items[index].is_empty():
            return put(items, kind, count, index)
    return false

static func take(items: Array[Dictionary], index: int, count: int = 1) -> void:
    items[index].count -= count
    if items[index].count == 0:
        items[index] = {}

func consume(kind: String) -> bool:
    for index in range(cells.size()):
        if cells[index].get("kind", "") == kind:
            take(cells, index)
            return true
    return false

# Plan on copies; failed drops never mutate inventory or equipped programs.
func plan(source: Dictionary, target: Dictionary, programs: Dictionary) -> Dictionary:
    if source.is_empty() or target.is_empty():
        return {}
    var items: Array[Dictionary] = cells.duplicate(true)
    var lists: Dictionary = programs.duplicate(true)
    var from_cell := int(source.get("cell", -1))
    var from_node := int(source.get("node", -1))
    var from_slot := int(source.get("slot", -1))
    var to_cell := int(target.get("cell", -1))
    var to_node := int(target.get("node", -1))
    var to_slot := int(target.get("slot", -1))
    var kind := ""
    if source.has("cell"):
        if from_cell < 0 or from_cell >= items.size() or items[from_cell].is_empty():
            return {}
        kind = items[from_cell].kind
    else:
        if not lists.has(from_node) or from_slot < 0 or from_slot >= lists[from_node].size():
            return {}
        kind = lists[from_node][from_slot]
    if target.has("cell"):
        if to_cell < -1 or to_cell >= items.size():
            return {}
        if source.has("cell"):
            if to_cell < 0:
                return {}
            if to_cell != from_cell:
                if items[to_cell].get("kind", "") == kind:
                    items[to_cell].count += items[from_cell].count
                    items[from_cell] = {}
                else:
                    var other: Dictionary = items[to_cell]
                    items[to_cell] = items[from_cell]
                    items[from_cell] = other
        else:
            if to_cell >= 0 and not items[to_cell].is_empty() and items[to_cell].kind != kind:
                var replacement: String = items[to_cell].kind
                if replacement not in ["sword", "herb"]:
                    return {}
                take(items, to_cell)
                lists[from_node][from_slot] = replacement
                if not put(items, kind, 1, to_cell if items[to_cell].is_empty() else -1):
                    return {}
            else:
                if not put(items, kind, 1, to_cell):
                    return {}
                lists[from_node].remove_at(from_slot)
    else:
        if not lists.has(to_node) or kind not in ["sword", "herb"] or to_slot < -1 or to_slot >= lists[to_node].size():
            return {}
        if source.has("cell"):
            take(items, from_cell)
            if to_slot >= 0:
                var replaced: String = lists[to_node][to_slot]
                if not put(items, replaced, 1, from_cell if items[from_cell].is_empty() else -1):
                    return {}
                lists[to_node][to_slot] = kind
            else:
                lists[to_node].append(kind)
        elif from_node == to_node:
            lists[from_node].remove_at(from_slot)
            lists[to_node].insert(lists[to_node].size() if to_slot == -1 else to_slot, kind)
        elif to_slot >= 0:
            lists[from_node][from_slot] = lists[to_node][to_slot]
            lists[to_node][to_slot] = kind
        else:
            lists[from_node].remove_at(from_slot)
            lists[to_node].append(kind)
    return {"cells": items, "programs": lists}
