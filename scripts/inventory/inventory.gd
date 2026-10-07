class_name Inventory
extends RefCounted
## Slot-based inventory with stacking, used both for the player's pack and for
## the base-camp chest (same class, different capacity).

signal changed()

var slots: Array[Dictionary] = []
var capacity: int = 24


func _init(p_capacity: int = 24) -> void:
	capacity = p_capacity
	slots.resize(capacity)
	for i in capacity:
		slots[i] = {}


func is_empty_slot(i: int) -> bool:
	return i < 0 or i >= slots.size() or slots[i].is_empty()


func item_at(i: int) -> String:
	if is_empty_slot(i):
		return ""
	return str(slots[i].get("id", ""))


func count_at(i: int) -> int:
	if is_empty_slot(i):
		return 0
	return int(slots[i].get("n", 0))


## Add items, filling partial stacks first. Returns the amount that did NOT
## fit, so callers can spill the remainder on the ground.
func add(item_id: String, amount: int = 1) -> int:
	if amount <= 0 or item_id.is_empty():
		return 0
	var def := ItemDB.get_item(item_id)
	var left := amount

	for i in slots.size():
		if left <= 0:
			break
		if item_at(i) != item_id:
			continue
		var room: int = def.stack_size - count_at(i)
		if room <= 0:
			continue
		var take: int = mini(room, left)
		slots[i]["n"] = count_at(i) + take
		left -= take

	for i in slots.size():
		if left <= 0:
			break
		if not is_empty_slot(i):
			continue
		var take: int = mini(def.stack_size, left)
		slots[i] = {"id": item_id, "n": take}
		left -= take

	if left != amount:
		changed.emit()
		EventBus.inventory_changed.emit()
	return left


func count(item_id: String) -> int:
	var total := 0
	for i in slots.size():
		if item_at(i) == item_id:
			total += count_at(i)
	return total


func has(item_id: String, amount: int = 1) -> bool:
	return count(item_id) >= amount


## Remove up to `amount`; returns how many were actually removed.
func remove(item_id: String, amount: int = 1) -> int:
	var left := amount
	# Drain the smallest stacks first so big stacks stay tidy.
	var indices: Array[int] = []
	for i in slots.size():
		if item_at(i) == item_id:
			indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool: return count_at(a) < count_at(b))
	for i in indices:
		if left <= 0:
			break
		var take: int = mini(count_at(i), left)
		var remaining: int = count_at(i) - take
		if remaining <= 0:
			slots[i] = {}
		else:
			slots[i]["n"] = remaining
		left -= take
	var removed := amount - left
	if removed > 0:
		changed.emit()
		EventBus.inventory_changed.emit()
	return removed


func remove_at(i: int, amount: int = 1) -> int:
	if is_empty_slot(i):
		return 0
	var take: int = mini(count_at(i), amount)
	var remaining: int = count_at(i) - take
	if remaining <= 0:
		slots[i] = {}
	else:
		slots[i]["n"] = remaining
	changed.emit()
	EventBus.inventory_changed.emit()
	return take


## Swap, or merge if the two slots hold the same stackable item.
func move(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= slots.size() or to >= slots.size():
		return
	var a: Dictionary = slots[from]
	var b: Dictionary = slots[to]
	if a.is_empty():
		return
	if not b.is_empty() and str(a.get("id")) == str(b.get("id")):
		var def := ItemDB.get_item(str(a.get("id")))
		var room: int = def.stack_size - int(b.get("n", 0))
		var take: int = mini(room, int(a.get("n", 0)))
		if take > 0:
			slots[to]["n"] = int(b.get("n", 0)) + take
			var left: int = int(a.get("n", 0)) - take
			slots[from] = {} if left <= 0 else {"id": str(a.get("id")), "n": left}
			changed.emit()
			EventBus.inventory_changed.emit()
			return
	slots[from] = b
	slots[to] = a
	changed.emit()
	EventBus.inventory_changed.emit()


func first_index_of(item_id: String) -> int:
	for i in slots.size():
		if item_at(i) == item_id:
			return i
	return -1


func used_slots() -> int:
	var n := 0
	for i in slots.size():
		if not is_empty_slot(i):
			n += 1
	return n


func is_full() -> bool:
	return used_slots() >= capacity


func clear() -> void:
	for i in slots.size():
		slots[i] = {}
	changed.emit()
	EventBus.inventory_changed.emit()


## Flat list of {id, n} for anything held — used by the death-drop system.
func contents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in slots.size():
		if is_empty_slot(i):
			continue
		out.append({"id": item_at(i), "n": count_at(i)})
	return out


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var packed: Array = []
	for i in slots.size():
		if is_empty_slot(i):
			packed.append(null)
		else:
			packed.append({"id": item_at(i), "n": count_at(i)})
	return {"capacity": capacity, "slots": packed}


func from_dict(d: Dictionary) -> void:
	capacity = maxi(1, int(d.get("capacity", capacity)))
	slots.resize(capacity)
	for i in capacity:
		slots[i] = {}
	var packed: Array = d.get("slots", [])
	for i in mini(packed.size(), capacity):
		var e = packed[i]
		if e == null or not (e is Dictionary):
			continue
		var id := str((e as Dictionary).get("id", ""))
		var n := int((e as Dictionary).get("n", 0))
		# Drop entries whose item no longer exists, rather than keeping a
		# phantom stack that would crash the UI.
		if id.is_empty() or n <= 0 or not ItemDB.has(id):
			continue
		slots[i] = {"id": id, "n": n}
	changed.emit()
	EventBus.inventory_changed.emit()
