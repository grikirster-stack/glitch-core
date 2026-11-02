extends RefCounted
class_name LoreDump
## Печать лора по сиду — чтобы читать текст глазами на ревью (ADR-001, § 4.9; issue #26).
##
## Запуск (мир не генерируется, поэтому за секунду):
##   godot --headless --path . -- --lore-dump --seed=31337
## Флаг разбирает scripts/main.gd: он вызывает LoreDump.dump(seed) и выходит.

## Статистика для примера эпилога: смены, фантомы, смерти, секунды.
const SAMPLE_STATS: Dictionary = {"days": 6, "kills": 23, "deaths": 1, "time": 3120.0}


## Собирает лор по сиду и печатает его.
static func dump(p_seed: int) -> void:
	Lore.generate(p_seed)
	print(text(p_seed))


## Весь лор текущего сида одним текстом: экипаж, места, главы, обрывки, эпитафии, эпилог.
static func text(p_seed: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("== ЛОР · сид %d ==" % p_seed)
	lines.append("")
	lines.append("Экипаж «Кербер-9»:")
	for c in Lore.crew:
		var mark: String = "   <-- НЕ ТОТ" if c["impostor"] else ""
		var sex: String = "ж" if c["gender"] == "f" else "м"
		lines.append("  %d. %-8s %s, «%s», %s%s" % [int(c["idx"]) + 1, c["role"], c["full"], c["callsign"], sex, mark])
	lines.append("")
	lines.append("Места:")
	lines.append("  кристальный биом: %s" % Lore.place_name("crystal", 0))
	for i in 4:
		lines.append("  тоннель %d: %s" % [i + 1, Lore.place_name("tunnel", i)])
	for i in 7:
		var holder: Dictionary = Lore.ruin_owner(i)
		lines.append("  руина %d: %s (хозяин: %s, %s)" % [i + 1, Lore.place_name("ruin", i), holder["full"], holder["role"]])
	for i in 2:
		lines.append("  база %d: %s" % [i + 1, Lore.place_name("base", i)])
	lines.append("")
	lines.append("Журнал:")
	for i in Lore.chapter_count():
		var a: Dictionary = Lore.chapter_author(i)
		lines.append("")
		lines.append("Глава %d. %s" % [i + 1, Lore.chapter_title(i)])
		lines.append("  [%s — %s %s, «%s»]" % [Lore.chapter_place(i), a["role"], a["full"], a["callsign"]])
		lines.append("  " + Lore.chapter(i))
	lines.append("")
	lines.append("Обрывки для чёрных ящиков (все %d):" % Lore.fragment_count())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = p_seed
	for i in Lore.fragment_count():
		lines.append("  - " + Lore.fragment_at(i, rng))
	lines.append("")
	lines.append("Эпитафии (по порядку выдачи):")
	for i in 4:
		lines.append("  - " + Lore.epitaph())
	lines.append("")
	lines.append("Эпилог:")
	for row in Lore.epilogue(SAMPLE_STATS).split("\n"):
		lines.append("  " + row)
	return "\n".join(lines)
