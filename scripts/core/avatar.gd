class_name Avatar
extends RefCounted
## Шов рисования героя (ADR-002 § 4.6, D8; MP-B, #87): Avatar.draw(canvas,
## layout, look, state). Его зовут Player._draw и превью главного меню; дальше —
## превью в лобби и двойник (MP-J).
##
## Здесь нынешний рисунок героя, перенесённый из Player._draw без изменений:
## при look = 0 картинка побайтно прежняя. От look сейчас зависит только цвет
## скафандра (8 цветов-заглушек, индекс 0 — нынешний красный). Облик скафандра
## «Кербер-9» (шлем, руки, баллоны, палитра) проектирует ADR-003 (#84); его
## вводит отдельный PR MP-L (#97), меняя только этот файл и Player.body_layout().
##
## layout — Player.body_layout(): части уже отзеркалены по facing (шов #58).
## state — {"hiding": bool, "flash": 0..1 (покраснение после урона),
##          "breath": фаза дыхания (мигание огонька)}; нет ключа — значение покоя.

## Размер корпуса героя — Player.SIZE (равенство проверяет menu_test). Своя
## константа, чтобы шов не тянул за собой player.gd и автозагрузки мира: превью
## меню и тесты в режиме --script грузят Avatar без них.
const SIZE: Vector2 = Vector2(12.0, 22.0)

## Сколько вариантов у каждой части Look (Profile.Look.COLOR..PACK) в этой сборке.
## «Случайно» в меню выбирает только из них; индекс вне — рисуется как 0.
const VARIANTS: PackedInt32Array = [8, 1, 1, 1]

## Цвета скафандра — заглушки до палитры ADR-003. Индекс 0 — нынешний красный.
const SUIT_COLORS: Array[Color] = [
	Color(0.86, 0.22, 0.24),   # красный — герой до ADR-002
	Color(0.92, 0.52, 0.18),   # оранжевый
	Color(0.90, 0.80, 0.24),   # жёлтый
	Color(0.32, 0.70, 0.30),   # зелёный
	Color(0.20, 0.66, 0.66),   # бирюзовый
	Color(0.28, 0.42, 0.86),   # синий
	Color(0.58, 0.34, 0.80),   # фиолетовый
	Color(0.80, 0.80, 0.78),   # светло-серый
]
## Подписи вариантов для меню, по частям.
const VARIANT_NAMES: Array = [
	["Красный", "Оранжевый", "Жёлтый", "Зелёный", "Бирюзовый", "Синий", "Фиолетовый", "Серый"],
	["Стандартный визор"],
	["Огонёк на шлеме"],
	["Стандартный рюкзак"],
]


## Индекс части i для рисования: неизвестный этой сборке (≥ VARIANTS[i]) — 0.
static func resolve(look: int, i: int) -> int:
	var idx: int = Profile.Look.part(look, i)
	return idx if idx < VARIANTS[i] else 0


## Цвет скафандра по look (неизвестный индекс — цвет 0).
static func suit_color(look: int) -> Color:
	return SUIT_COLORS[resolve(look, Profile.Look.COLOR)]


static func variant_name(i: int, idx: int) -> String:
	var names: Array = VARIANT_NAMES[i]
	return String(names[idx]) if idx >= 0 and idx < names.size() else String(names[0])


## Случайный вид из вариантов VARIANTS. rng — свой генератор вызывающего.
static func random_look(rng: RandomNumberGenerator) -> int:
	var parts: PackedInt32Array = PackedInt32Array()
	for i in Profile.Look.PARTS:
		parts.append(rng.randi_range(0, VARIANTS[i] - 1))
	return Profile.Look.pack(parts)


## Рисует героя на canvas (внутри его _draw) в локальных координатах героя.
static func draw(canvas: CanvasItem, lay: Dictionary, look: int, state: Dictionary) -> void:
	var size: Vector2 = SIZE
	var hiding: bool = state.get("hiding", false)
	var flash: float = state.get("flash", 0.0)
	var breath: float = state.get("breath", 0.0)
	# То же, что suit_color(look), без вызовов: шов зовут каждый кадр.
	var ci: int = look & 0xF
	var body_col: Color = SUIT_COLORS[ci if ci < SUIT_COLORS.size() else 0]
	if hiding:
		body_col = body_col.darkened(0.45)
	# Покраснение корпуса после урона.
	if flash > 0.0:
		body_col = body_col.lerp(Color(1.0, 0.74, 0.64), flash * 0.85)
	# Фигура уже отзеркалена по facing (body_layout), рисуем как есть.
	var r: Rect2 = lay["body"]
	# Тень
	canvas.draw_set_transform(Vector2(0, size.y * 0.5), 0.0, Vector2(1.0, 0.35))
	canvas.draw_circle(Vector2.ZERO, size.x * 0.6, Color(0, 0, 0, 0.28))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Рюкзак (Look.PACK — пока один вариант)
	canvas.draw_rect(lay["backpack"], body_col.darkened(0.25))
	# Тело
	canvas.draw_rect(r, body_col)
	canvas.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), body_col.lightened(0.18))
	canvas.draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), body_col.darkened(0.22))
	# Ноги
	canvas.draw_rect(lay["leg_back"], body_col.darkened(0.35))
	canvas.draw_rect(lay["leg_front"], body_col.darkened(0.35))
	# Визор (Look.HELMET — пока один вариант)
	canvas.draw_rect(lay["visor"], Color(0.72, 0.86, 0.94))
	canvas.draw_rect(lay["visor_top"], Color(0.88, 0.96, 1.0))
	canvas.draw_rect(lay["visor_glint"], Color(1, 1, 1, 0.85))
	# Мигающий «свет» на шлеме (Look.ACCESSORY — пока один вариант)
	var blink: float = 0.5 + 0.5 * sin(breath * 6.0)
	canvas.draw_circle(lay["light"], 1.6, Color(1.0, 0.35, 0.3, 0.5 + blink * 0.5))
	# Контур урона
	if flash > 0.0:
		canvas.draw_rect(r, Color(1.0, 0.35, 0.32, flash * 0.8), false, 1.5)

	if hiding:
		canvas.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(0.4, 0.9, 1.0, 0.5), 1.5)
