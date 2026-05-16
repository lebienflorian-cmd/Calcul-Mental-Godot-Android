extends Node
# ============================================================
# CALC GENERATOR — Génère des expressions arithmétiques selon options.
# Renvoie {expr_str, value, operands, ops}.
# ============================================================

const OP_ADD := "+"
const OP_SUB := "−"
const OP_MUL := "×"
const OP_DIV := "÷"

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

# ---- API principale ----
func generate() -> Dictionary:
	# Cas Flash Anzan : on génère plutôt une LISTE de nombres
	if GameState.options.mode == GameState.Mode.FLASH_ANZAN:
		return _generate_anzan()
	if GameState.options.mode == GameState.Mode.INFERNAL:
		return _generate_infernal()
	return _generate_classic()

# ---- Génération anzan ----
func _generate_anzan() -> Dictionary:
	var count: int = GameState.options.flash_count
	var numbers: Array = []
	var sum := 0
	var size_max := _max_number_for_size()
	for i in count:
		var n := _rng.randi_range(1, max(9, size_max / 10))
		numbers.append(n)
		sum += n
	return {
		"expr_str": "Flash Anzan",
		"value": float(sum),
		"numbers": numbers,
		"is_anzan": true,
	}

# ---- Génération mode infernal (simple, contrôlé) ----
func _generate_infernal() -> Dictionary:
	var a := _rng.randi_range(1, 9)
	var b := _rng.randi_range(1, 9)
	var op := OP_ADD if _rng.randf() < 0.5 else OP_SUB
	var val := (a + b) if op == OP_ADD else (a - b)
	if val < 0 and GameState.options.positive_only:
		# swap
		var tmp := a; a = b; b = tmp
		val = a - b
	var expr := "%d %s %d" % [a, op, b]
	return {"expr_str": expr, "value": float(val), "operands": [a, b], "ops": [op]}

# ---- Génération classique ----
func _generate_classic() -> Dictionary:
	for attempt in 50:
		var d := _try_generate_classic()
		if d != null and _validate(d):
			return d
	# Fallback ultra-simple
	var a := _rng.randi_range(2, 9)
	var b := _rng.randi_range(2, 9)
	return {"expr_str": "%d + %d" % [a, b], "value": float(a + b), "operands": [a, b], "ops": [OP_ADD]}

func _try_generate_classic():
	var ops_active := _active_ops()
	if ops_active.is_empty():
		ops_active = [OP_ADD]

	var min_ops: int = GameState.options.operand_min
	var max_ops: int = GameState.options.operand_max
	min_ops = max(2, min_ops)
	max_ops = max(min_ops, max_ops)
	var n_operands := _rng.randi_range(min_ops, max_ops)

	# Sub no-borrow : forcer 2 opérandes
	if GameState.options.sub_no_borrow and OP_SUB in ops_active:
		n_operands = 2

	# Choisir opérations
	var ops: Array = []
	var op_chosen: String = ops_active[_rng.randi() % ops_active.size()]
	for i in n_operands - 1:
		if GameState.options.mix_ops:
			ops.append(ops_active[_rng.randi() % ops_active.size()])
		else:
			ops.append(op_chosen)

	# Choisir opérandes
	var operands: Array = []
	for i in n_operands:
		operands.append(_gen_number())

	# Cas multiplication & tables limitées
	if GameState.options.limit_tables and OP_MUL in ops:
		var tmax: int = GameState.options.tables_max
		for i in operands.size():
			operands[i] = clamp(operands[i], 1, tmax)

	# Division entière : ajuster
	if OP_DIV in ops:
		operands = _fix_for_integer_div(operands, ops)

	# Add no-carry
	if GameState.options.add_no_carry and OP_ADD in ops and operands.size() == 2:
		operands = _fix_no_carry_add(operands)

	# Sub no-borrow
	if GameState.options.sub_no_borrow and OP_SUB in ops and operands.size() == 2:
		operands = _fix_no_borrow_sub(operands)

	# Parenthèses (optionnel, sauf division)
	var use_paren := GameState.options.parentheses and not (OP_DIV in ops) and n_operands >= 3
	var expr_str := _build_expr(operands, ops, use_paren)
	var value = _evaluate(operands, ops)

	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return null

	return {
		"expr_str": expr_str,
		"value": float(value),
		"operands": operands,
		"ops": ops,
	}

# ---- Helpers ----
func _active_ops() -> Array:
	var a := []
	if GameState.options.op_add: a.append(OP_ADD)
	if GameState.options.op_sub: a.append(OP_SUB)
	if GameState.options.op_mul: a.append(OP_MUL)
	if GameState.options.op_div: a.append(OP_DIV)
	return a

func _gen_number() -> int:
	var ranges := []
	if GameState.options.size_units:     ranges.append([0, 9])
	if GameState.options.size_tens:      ranges.append([10, 99])
	if GameState.options.size_hundreds:  ranges.append([100, 999])
	if GameState.options.size_thousands: ranges.append([1000, 9999])
	if GameState.options.size_tenk:      ranges.append([10000, 99999])
	if GameState.options.size_hundk:     ranges.append([100000, 999999])
	if ranges.is_empty(): ranges = [[1, 9]]
	var r = ranges[_rng.randi() % ranges.size()] if GameState.options.mix_sizes else ranges[0]
	var n := _rng.randi_range(r[0], r[1])
	if GameState.options.only_negative:
		n = -abs(n)
	elif GameState.options.allow_negative and _rng.randf() < 0.3:
		n = -n
	return n

func _fix_for_integer_div(operands: Array, ops: Array) -> Array:
	# Remplace les paires impliquées par des couples a, b avec a%b == 0
	var out := operands.duplicate()
	for i in ops.size():
		if ops[i] == OP_DIV:
			var divisor: int = max(1, abs(out[i + 1]))
			var quotient := _rng.randi_range(2, 12)
			out[i + 1] = divisor
			out[i] = divisor * quotient
	return out

func _fix_no_carry_add(operands: Array) -> Array:
	# Restreint chaque chiffre pour que la somme par colonne reste < 10
	var a: int = operands[0]
	var b: int = operands[1]
	var sa := str(abs(a))
	var sb := str(abs(b))
	var maxlen = max(sa.length(), sb.length())
	sa = sa.lpad(maxlen, "0")
	sb = sb.lpad(maxlen, "0")
	var new_b := ""
	for i in maxlen:
		var da := int(sa[i])
		var db := int(sb[i])
		if da + db > 9:
			db = max(0, 9 - da)
		new_b += str(db)
	var nb := int(new_b)
	if b < 0: nb = -nb
	return [a, nb]

func _fix_no_borrow_sub(operands: Array) -> Array:
	var a: int = operands[0]
	var b: int = operands[1]
	if abs(b) > abs(a):
		var t := a; a = b; b = t
	# chiffre par chiffre b[i] <= a[i]
	var sa := str(abs(a))
	var sb := str(abs(b))
	var maxlen = max(sa.length(), sb.length())
	sa = sa.lpad(maxlen, "0")
	sb = sb.lpad(maxlen, "0")
	var new_b := ""
	for i in maxlen:
		var da := int(sa[i])
		var db := int(sb[i])
		if db > da: db = da
		new_b += str(db)
	return [a, int(new_b)]

func _build_expr(operands: Array, ops: Array, use_paren: bool) -> String:
	var s := str(operands[0])
	for i in ops.size():
		var o = ops[i]
		var v = operands[i + 1]
		var vs := str(v) if v >= 0 else "(%d)" % v
		s += " %s %s" % [o, vs]
	if use_paren and operands.size() >= 3:
		# parenthèses autour des 2 premiers
		var first_two = "%s %s %s" % [operands[0], ops[0], operands[1]]
		var rest := ""
		for i in range(1, ops.size()):
			rest += " %s %s" % [ops[i], operands[i + 1]]
		s = "(" + first_two + ")" + rest
	return s

func _evaluate(operands: Array, ops: Array):
	# Évaluation gauche-à-droite SANS priorité (cohérent avec l'affichage simple)
	# Pour parenthèses : on regroupe les 2 premiers seulement.
	# Pour rester simple : on respecte la priorité × ÷ avant + −.
	var nums := operands.duplicate()
	var oplist := ops.duplicate()
	# 1ère passe : × ÷
	var i := 0
	while i < oplist.size():
		var o = oplist[i]
		if o == OP_MUL:
			nums[i] = nums[i] * nums[i + 1]
			nums.remove_at(i + 1)
			oplist.remove_at(i)
		elif o == OP_DIV:
			if nums[i + 1] == 0:
				return null
			var v: float = float(nums[i]) / float(nums[i + 1])
			nums[i] = v
			nums.remove_at(i + 1)
			oplist.remove_at(i)
		else:
			i += 1
	# 2e passe : + −
	var result = nums[0]
	for j in oplist.size():
		if oplist[j] == OP_ADD:
			result = result + nums[j + 1]
		else:
			result = result - nums[j + 1]
	return result

func _validate(d: Dictionary) -> bool:
	var v: float = d.value
	if GameState.options.positive_only and v < 0:
		return false
	if GameState.options.limit_result and abs(v) > GameState.options.result_max:
		return false
	# Pour div entière, le résultat doit être entier
	if OP_DIV in d.ops and GameState.options.integer_div:
		if v != float(int(v)):
			return false
	return true

func _max_number_for_size() -> int:
	if GameState.options.size_hundk:     return 999999
	if GameState.options.size_tenk:      return 99999
	if GameState.options.size_thousands: return 9999
	if GameState.options.size_hundreds:  return 999
	if GameState.options.size_tens:      return 99
	return 9
