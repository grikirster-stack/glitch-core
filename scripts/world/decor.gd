extends TileMapLayer
## Декор-слой флоры (ADR-003 V2, #104): «Пузырник», «полка» и дождевики на
## лишайнике, завеса гиф и трутовики в средних пещерах, мембранные мешки и
## трубки в глубине, стебель свечника в просветах его шляпок.
##
## Только картинка:
##  * отдельный TileMapLayer без физики и навигации — коллизий нет, проходимость
##    мира прежняя (TREE/LEAVES рисует атлас тайлов, их форма — World._place_tree);
##  * что и где растёт, выводится из сида мира (свой хэш, не ГСЧ генерации —
##    мир от декора не сдвигается) и текущих тайлов. В сохранение и в сеть не идёт:
##    каждая сторона считает декор сама из тех же сида и тайлов;
##  * учитывает туман войны (#59): клетки декора заводятся чанками CHUNK×CHUNK
##    только там, где игрок уже что-то исследовал (World.explored_changed); под
##    туманом декора нет вовсе. Слой лежит в мировом канвасе под FogLayer (z 30)
##    и под CanvasModulate — в полутени исследованного он притушен, ночью темнеет,
##    как тайлы. Своих источников света у декора нет (свечение — слой эмиссии V3).
##
## Стоимость: в кадре — ноль скрипта (рисует движок, как тайлы). Чанк собирается
## один раз, когда в нём открылась первая клетка (доли мс); новый мир или загрузка
## с другим рельефом сбрасывают слой (World._sync_all → reset). Правка клетки
## пересчитывает 8 клеток своего столбца (декор зависит только от столбца:
## пол/потолок над и под клеткой, ствол под шляпкой) — World._set_cell_visual.

const TILE: int = 16

## Виды декора. Код клетки в _code: 0 — пусто, иначе 1 + вид * ALTS + фактура.
enum K {
	BUBBLE_LO,     ## пузырник, нижняя клетка: нити и низкий пузырь
	BUBBLE_HI,     ## пузырник, верхняя клетка: связка квадратных пузырей
	SHELF,         ## низкая «полка»: пластины одна над другой
	PUFF,          ## дождевики: квадратные шарики на лишайнике
	HYPHAE_TOP,    ## завеса гиф с потолка, длинная (продолжается клеткой ниже)
	HYPHAE_LO,     ## нижняя клетка длинной завесы: светящиеся кончики
	HYPHAE_SHORT,  ## короткая завеса в одну клетку
	POLYPORE,      ## трутовик-полка на ножке, светится нижняя кромка
	SACS,          ## мембранные мешки на общем корне, светящееся ядро
	TUBES,         ## трубки, сочащиеся спорами
	STEM,          ## стебель свечника в просвете шляпки (над стволом)
}
const KINDS: int = 11
const ALTS: int = 2

## Насколько густо, из 1024: на лишайнике поверхности, у пола и потолка пещер.
const DENS_SURFACE: int = 190
const DENS_CEIL: int = 600        ## внутри грозди завесы
const DENS_CLUSTER: int = 560     ## доля гроздей завесы по 4 столбца
const DENS_FLOOR_MID: int = 110
const DENS_FLOOR_DEEP: int = 120
const DENS_FLOOR_TOP: int = 40
## Соль хэша декора: свой поток, не ГСЧ генерации мира.
const SALT: int = 0x44454352   # «DECR»

## Чанк сборки, клеток: мелкий — сборка при открытии не даёт пика в кадре.
const CHUNK: int = 16

# ---------------------------------------------- СЧЁТЧИКИ (для замеров)
var cells: int = 0             ## клеток с декором сейчас
var chunks_built: int = 0      ## собранных чанков
var build_us: int = 0          ## суммарное время сборки чанков с последнего reset, мкс
var build_us_max: int = 0      ## самый дорогой чанк, мкс
var update_calls: int = 0      ## правок клеток мира (on_cell)
var update_us: int = 0         ## суммарное время on_cell, мкс
var update_us_max: int = 0

var _code: PackedByteArray = PackedByteArray()
var _built: PackedByteArray = PackedByteArray()     ## чанк -> 1: собран
var _natural: PackedByteArray = PackedByteArray()   ## id -> 1: природная твёрдая порода (пол/потолок)
var _mix: int = 0
var _w: int = 0                ## World.W / World.H — в горячем цикле без обращений к узлу
var _hgt: int = 0
var _cx: int = 0               ## чанков по ширине / высоте
var _cy: int = 0


func _ready() -> void:
	name = "Decor"
	# Над тайлами (шляпка + стебель в просвете), под табличками (2), постройками (3),
	# героем и фантомами (5) и туманом войны (30).
	z_index = 1
	collision_enabled = false
	navigation_enabled = false
	tile_set = _build_tileset()
	_w = World.W
	_hgt = World.H
	_cx = (_w + CHUNK - 1) / CHUNK
	_cy = (_hgt + CHUNK - 1) / CHUNK
	World.explored_changed.connect(_on_explored)
	World.explored_reset.connect(_on_explored_reset)
	_natural.resize(IDs.TILE_COUNT)
	for id in [IDs.T.STONE, IDs.T.DIRT, IDs.T.GRASS, IDs.T.SAND, IDs.T.SANDSTONE,
			IDs.T.COPPER_ORE, IDs.T.IRON_ORE, IDs.T.CRYSTAL_ORE, IDs.T.COAL_ORE,
			IDs.T.SCRAP_ORE, IDs.T.BEDROCK]:
		_natural[id] = 1


# ------------------------------------------------------------ СБОРКА

## Тайлы мира заменены целиком (новый мир, загрузка с другим рельефом): слой
## пуст, чанки соберутся по исследованному — сразу и по мере открытия.
func reset() -> void:
	clear()
	_code.resize(_w * _hgt)
	_code.fill(0)
	_built.resize(_cx * _cy)
	_built.fill(0)
	_mix = _hash3(World.world_seed, SALT, 7)
	cells = 0
	chunks_built = 0
	build_us = 0
	build_us_max = 0
	# Карту исследования новому миру World выставит следом (explored_reset); здесь
	# она ещё прежняя. Отложенный проход — на случай пересборки без смены карты.
	_on_explored_reset.call_deferred()


## Собрать весь мир сразу, без оглядки на туман (инструменты, проверки).
func build_all() -> void:
	for ci in _cx * _cy:
		if _built[ci] == 0:
			_build_chunk(ci)


## Карта исследования заменена: собрать чанки, где открыта хоть одна клетка.
func _on_explored_reset() -> void:
	if _built.is_empty() or World.explore_cells <= 0:
		return
	var ex: PackedByteArray = World.explored
	if ex.size() != _w * _hgt:
		return
	for cy in _cy:
		var y1: int = mini((cy + 1) * CHUNK, _hgt)
		for cx in _cx:
			var ci: int = cy * _cx + cx
			if _built[ci] != 0:
				continue
			var x0: int = cx * CHUNK
			var x1: int = mini(x0 + CHUNK, _w)
			for y in range(cy * CHUNK, y1):
				if ex.slice(y * _w + x0, y * _w + x1).has(1):
					_build_chunk(ci)
					break


## Открылись клетки в прямоугольнике rect: собрать задетые чанки, если ещё нет.
func _on_explored(rect: Rect2i) -> void:
	if _built.is_empty():
		return
	var cx0: int = clampi(rect.position.x / CHUNK, 0, _cx - 1)
	var cx1: int = clampi((rect.end.x - 1) / CHUNK, 0, _cx - 1)
	var cy0: int = clampi(rect.position.y / CHUNK, 0, _cy - 1)
	var cy1: int = clampi((rect.end.y - 1) / CHUNK, 0, _cy - 1)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if _built[cy * _cx + cx] == 0:
				_build_chunk(cy * _cx + cx)


## Сборка чанка по тайлам мира. Кандидаты отсеиваются по массиву тайлов без
## вызовов — те же условия, что открывают ветки _eval: пустая клетка на полу,
## под потолком, над пузырником или под завесой; шляпка свечника.
func _build_chunk(ci: int) -> void:
	var t0: int = Time.get_ticks_usec()
	_built[ci] = 1
	chunks_built += 1
	var tl: PackedByteArray = World.tiles
	var w: int = _w
	if tl.size() != w * _hgt:
		return
	var x0: int = (ci % _cx) * CHUNK
	var x1: int = mini(x0 + CHUNK, w)
	var y0: int = maxi((ci / _cx) * CHUNK, 2)
	var y1: int = mini((ci / _cx) * CHUNK + CHUNK, _hgt - 2)
	var nat: PackedByteArray = _natural
	var air: int = IDs.T.AIR
	var leaves: int = IDs.T.LEAVES
	var grass: int = IDs.T.GRASS
	for y in range(y0, y1):
		var row: int = y * w
		for x in range(x0, x1):
			var i: int = row + x
			var t: int = tl[i]
			if t == air:
				var b: int = tl[i + w]
				if nat[b] == 0:
					var a: int = tl[i - w]
					if nat[a] == 0 and (b != air or (tl[i + w + w] != grass
							and (a != air or nat[tl[i - w - w]] == 0))):
						continue
			elif t != leaves:
				continue
			var c: int = _eval(tl, x, y)
			if c != 0:
				_code[i] = c
				set_cell(Vector2i(x, y), 0, Vector2i(c - 1, 0))
				cells += 1
	var us: int = Time.get_ticks_usec() - t0
	build_us += us
	build_us_max = maxi(build_us_max, us)


## Клетка мира (x, y) сменила тайл: пересчитать декор её столбца, который от
## неё зависит (стебель — до 5 клеток выше, завеса и пузырник — до 2 ниже).
## Несобранные чанки пропускаем: соберутся из тех же тайлов, когда их откроют.
func on_cell(x: int, y: int) -> void:
	if _built.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	var w: int = _w
	var tl: PackedByteArray = World.tiles
	var cxx: int = x / CHUNK
	for cy in range(maxi(y - 5, 0), mini(y + 3, _hgt)):
		if _built[(cy / CHUNK) * _cx + cxx] == 0:
			continue
		var c: int = _eval(tl, x, cy)
		var i: int = cy * w + x
		if c == _code[i]:
			continue
		if c == 0:
			cells -= 1
			erase_cell(Vector2i(x, cy))
		else:
			if _code[i] == 0:
				cells += 1
			set_cell(Vector2i(x, cy), 0, Vector2i(c - 1, 0))
		_code[i] = c
	var us: int = Time.get_ticks_usec() - t0
	update_calls += 1
	update_us += us
	update_us_max = maxi(update_us_max, us)


## Код декора клетки (0 — пусто или чанк ещё не собран: под туманом).
func decor_at(x: int, y: int) -> int:
	if _code.is_empty() or x < 0 or y < 0 or x >= _w or y >= _hgt:
		return 0
	return _code[y * _w + x]


## Каким был бы декор клетки по нынешним тайлам (для проверок: собранный слой
## должен совпадать с этим везде, где чанк собран).
func expected_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _w or y >= _hgt:
		return 0
	return _eval(World.tiles, x, y)


## Собран ли чанк с клеткой c (декор заведён).
func is_built(c: Vector2i) -> bool:
	if _built.is_empty() or c.x < 0 or c.y < 0 or c.x >= _w or c.y >= _hgt:
		return false
	return _built[(c.y / CHUNK) * _cx + c.x / CHUNK] != 0


## Вид декора по коду клетки (-1 — пусто).
static func kind_of(code: int) -> int:
	return -1 if code == 0 else (code - 1) / ALTS


# ------------------------------------------------------------ ПРАВИЛА

## Только по массиву тайлов tl и столбцу x: соседи по горизонтали не нужны, поэтому
## правка клетки трогает декор лишь своего столбца. Дешёвые проверки (тайл, хэш) —
## раньше дорогих (биом); фактура берётся из того же хэша, что и решение «растёт».
func _eval(tl: PackedByteArray, x: int, y: int) -> int:
	var w: int = _w
	if y < 2 or y >= _hgt - 2:
		return 0
	var i: int = y * w + x
	var t: int = tl[i]
	if t == IDs.T.LEAVES:
		# Шляпка над стволом: в её просвете виден стебель.
		var j: int = i
		for k in mini(5, _hgt - 1 - y):
			j += w
			var b: int = tl[j]
			if b == IDs.T.TREE:
				return _code_of(K.STEM, _h(x, y, 1))
			if b != IDs.T.LEAVES:
				return 0
		return 0
	if t != IDs.T.AIR:
		return 0
	var below: int = tl[i + w]
	if _natural[below] != 0:
		var hv: int = _h(x, y, 4)
		var k: int = _floor_kind(tl, x, y, below, hv)
		if k >= 0:
			return _code_of(k, hv)
	elif below == IDs.T.AIR and tl[i + w + w] == IDs.T.GRASS:
		# Верх пузырника, растущего клеткой ниже.
		var hb: int = _h(x, y + 1, 4)
		if _floor_kind(tl, x, y + 1, IDs.T.GRASS, hb) == K.BUBBLE_LO:
			return _code_of(K.BUBBLE_HI, hb)
	var above: int = tl[i - w]
	if _natural[above] != 0:
		var hc: int = _h(x, y, 6)
		if _ceil_hyphae(x, y, hc):
			var long: bool = below == IDs.T.AIR and tl[i + w + w] == IDs.T.AIR
			return _code_of(K.HYPHAE_TOP if long else K.HYPHAE_SHORT, hc)
	elif above == IDs.T.AIR and below == IDs.T.AIR and _natural[tl[i - w - w]] != 0:
		# Низ длинной завесы, свисающей с потолка клеткой выше.
		var hl: int = _h(x, y - 1, 6)
		if _ceil_hyphae(x, y - 1, hl):
			return _code_of(K.HYPHAE_LO, hl)
	return 0


## Что растёт в пустой клетке (x, y) на полу floor_id (-1 — ничего); hv — хэш клетки.
func _floor_kind(tl: PackedByteArray, x: int, y: int, floor_id: int, hv: int) -> int:
	var r: int = hv & 1023
	if r >= DENS_SURFACE:   # самая густая из плотностей — отсев до биома
		return -1
	var pick: int = (hv >> 10) & 1023
	if floor_id == IDs.T.GRASS:
		if pick < 380 and tl[(y - 1) * _w + x] == IDs.T.AIR:
			return K.BUBBLE_LO
		return K.SHELF if pick < 700 else K.PUFF
	match World.biome_at(x, y):
		1:
			return K.POLYPORE if r < DENS_FLOOR_MID else -1
		2:
			if r >= DENS_FLOOR_DEEP:
				return -1
			return K.SACS if pick < 640 else K.TUBES
	# Пещеры под поверхностью: изредка «полка».
	return K.SHELF if r < DENS_FLOOR_TOP and y > World.surface[x] else -1


## Свисает ли завеса гиф с потолка над пустой клеткой (x, y): средние пещеры,
## гроздьями — соседние столбцы делят «гроздь» по x / 4. hv — хэш клетки.
func _ceil_hyphae(x: int, y: int, hv: int) -> bool:
	if (hv & 1023) >= DENS_CEIL:
		return false
	if (_h(x >> 2, y, 5) & 1023) >= DENS_CLUSTER:
		return false
	return World.biome_at(x, y) == 1


## Код клетки: вид и фактура (бит 20 хэша — не тот, что решал «растёт»).
func _code_of(kind: int, hv: int) -> int:
	return 1 + kind * ALTS + ((hv >> 20) & (ALTS - 1))


## Хэш клетки от сида мира и соли — без состояния, одинаков на всех сторонах.
func _h(x: int, y: int, salt: int) -> int:
	var v: int = (x * 0x27D4EB2D + y * 0x165667B1 + salt * 0x61C88647 + _mix) & 0x7FFFFFFF
	v = ((v ^ (v >> 15)) * 0x2C1B3C6D) & 0x7FFFFFFF
	v = ((v ^ (v >> 12)) * 0x297A2D39) & 0x7FFFFFFF
	return v ^ (v >> 15)


static func _hash3(a: int, b: int, c: int) -> int:
	var v: int = (a * 0x27D4EB2D + b * 0x165667B1 + c * 0x61C88647) & 0x7FFFFFFF
	v = ((v ^ (v >> 15)) * 0x2C1B3C6D) & 0x7FFFFFFF
	v = ((v ^ (v >> 12)) * 0x297A2D39) & 0x7FFFFFFF
	return v ^ (v >> 15)


# ------------------------------------------------------------ РИСУНОК

## Атлас декора: один ряд, KINDS × ALTS клеток 16×16; вторая фактура — зеркальная
## и с другим разбросом. Только прямоугольники (ADR-003 § 3.1).
func _build_tileset() -> TileSet:
	var img: Image = Image.create_empty(KINDS * ALTS * TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for k in KINDS:
		for a in ALTS:
			img.blit_rect(paint(k, a), Rect2i(0, 0, TILE, TILE), Vector2i((k * ALTS + a) * TILE, 0))
	var ts: TileSet = TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in KINDS * ALTS:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	return ts


## Картинка 16×16 одного вида декора (галерея и атлас).
static func paint(kind: int, alt: int) -> Image:
	var t: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	t.fill(Color(0, 0, 0, 0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7331 + kind * 101 + alt * 17
	match kind:
		K.BUBBLE_LO, K.BUBBLE_HI:
			_paint_bubbles(t, kind == K.BUBBLE_HI, alt)
		K.SHELF:
			_paint_shelf(t, alt)
		K.PUFF:
			_paint_puff(t, rng)
		K.HYPHAE_TOP, K.HYPHAE_LO, K.HYPHAE_SHORT:
			_paint_hyphae(t, kind, alt)
		K.POLYPORE:
			_paint_polypore(t, alt)
		K.SACS:
			_paint_sacs(t, alt)
		K.TUBES:
			_paint_tubes(t, rng)
		K.STEM:
			# Стебель в просвете шляпки: та же кисть, что у тайла TREE.
			DB.paint_flora_stem(t, DB.CAP_H, TILE, alt * 2 + 1)
	if alt == 1 and kind != K.STEM:
		t.flip_x()
	return t


static func _r(t: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var rc: Rect2i = Rect2i(x, y, w, h).intersection(Rect2i(0, 0, TILE, TILE))
	if rc.has_area():
		t.fill_rect(rc, c)


## «Пузырник»: связка квадратных сиреневых пузырей на нитях. Нижняя клетка —
## нити от земли и один низкий пузырь, верхняя — пузыри на разной высоте.
## Нити в двух клетках стоят в одних и тех же столбцах — связка цельная.
static func _paint_bubbles(t: Image, hi: bool, alt: int) -> void:
	var b: Color = DB.pal("fl2")
	var bd: Color = DB.pal("fl2_d")
	var xs: Array = [2, 6, 10, 13]
	var tops: Array = [3, 9, 1, 6] if alt == 0 else [7, 2, 10, 4]
	for i in xs.size():
		var x: int = xs[i]
		if hi:
			var by: int = tops[i]
			_r(t, x, by + 4, 1, TILE - by - 4, bd)
			_r(t, x - 2, by, 5, 5, Color(b.r, b.g, b.b, 0.9))
			_r(t, x - 2, by, 5, 1, b.lightened(0.25))
			_r(t, x + 2, by + 1, 1, 4, bd)
			t.set_pixel(x - 1, by + 1, Color(1, 1, 1, 0.85))
		else:
			_r(t, x, 0, 1, TILE, bd)
	if not hi:
		# Один пузырь пониже, у самой земли.
		var lx: int = 10 if alt == 0 else 6
		_r(t, lx - 1, 6, 4, 4, Color(b.r, b.g, b.b, 0.9))
		_r(t, lx - 1, 6, 4, 1, b.lightened(0.25))
		_r(t, lx + 2, 7, 1, 3, bd)


## Низкая «полка»: плоские пластины одна над другой на коротком стебле.
static func _paint_shelf(t: Image, alt: int) -> void:
	var st: Color = DB.pal("fl3")
	var cap: Color = DB.pal("fl1")
	var capd: Color = DB.pal("fl1_d")
	_r(t, 2, 12, 12, 2, capd)
	_r(t, 4, 9, 8, 2, cap)
	_r(t, 4, 9, 8, 1, cap.lightened(0.2))
	if alt == 1:
		_r(t, 5, 6, 6, 2, cap)
		_r(t, 5, 6, 6, 1, cap.lightened(0.2))
	_r(t, 7, 6 if alt == 1 else 9, 2, 10 if alt == 1 else 7, st)
	_r(t, 8, 6 if alt == 1 else 9, 1, 10 if alt == 1 else 7, st.darkened(0.18))


## Дождевики: квадратные шарики-споровики на лишайнике, с бликом и «порой» сверху.
static func _paint_puff(t: Image, rng: RandomNumberGenerator) -> void:
	var c: Color = DB.pal("fl3")
	var sizes: Array = [5, 3, 4]
	var xs: Array = [2, 8, 11]
	for i in sizes.size():
		var s: int = sizes[i]
		var x: int = xs[i] + rng.randi_range(-1, 0)
		var y: int = TILE - s
		_r(t, x, y, s, s, c)
		_r(t, x, y, s, 1, c.lightened(0.1))
		_r(t, x + s - 1, y + 1, 1, s - 1, c.darkened(0.2))
		_r(t, x, TILE - 1, s, 1, DB.pal("s_top").darkened(0.1))
		t.set_pixel(x + s / 2, y, DB.pal("fl1_d"))


## Завеса мицелия: нити через столбец, кончики светятся бирюзой. Длинная завеса
## (TOP + LO) тянет часть нитей через границу клеток в тех же столбцах.
static func _paint_hyphae(t: Image, kind: int, alt: int) -> void:
	var thread: Color = DB.pal("m_hi").lerp(DB.pal("m_glow"), 0.25)
	var glow: Color = DB.pal("m_glow")
	var core: Color = DB.pal("bio_core")
	for k in 7:
		var x: int = 1 + k * 2
		# Длина нити в пикселях от потолка: 4..28, своя у столбца и фактуры.
		var l: int = 4 + ((k * 7 + alt * 5 + 3) * 11) % 25
		if kind == K.HYPHAE_SHORT:
			l = 3 + ((k * 5 + alt * 3 + 1) * 7) % 12
		var y0: int = 0 if kind != K.HYPHAE_LO else -TILE
		var tip: int = y0 + l
		if kind == K.HYPHAE_LO and tip < 0:
			continue
		_r(t, x, y0, 1, l, thread)
		if tip - 1 >= 0 and tip - 1 < TILE:
			t.set_pixel(x, tip - 1, glow)
		if tip >= 0 and tip < TILE:
			t.set_pixel(x, tip, core if (k + alt) % 3 == 0 else glow)


## Трутовик: две полки на ножке, нижняя кромка каждой светится.
static func _paint_polypore(t: Image, alt: int) -> void:
	var glow: Color = DB.pal("m_glow")
	var top: int = 1 + alt
	_r(t, 7, top + 1, 2, TILE - top - 1, DB.pal("m_hi"))
	_r(t, 2, 6 + alt, 12, 2, DB.pal("fl2_d"))
	_r(t, 4, top, 9, 2, DB.pal("fl2"))
	_r(t, 4, top, 9, 1, DB.pal("fl2").lightened(0.2))
	_r(t, 4, 8 + alt, 8, 1, glow)
	_r(t, 5, top + 2, 7, 1, glow)


## Мембранные мешки на общем корне: квадрат в квадрате, светящееся ядро; над
## большим мешком — трубки со спорами.
static func _paint_sacs(t: Image, alt: int) -> void:
	var hi: Color = DB.pal("d_hi")
	var glow: Color = DB.pal("d_glow")
	var inner: Color = Color("#C8786A")
	var lite: Color = Color("#E8A090")
	_r(t, 0, 14, 16, 2, hi)
	var sacs: Array = [[1, 7, 6], [7, 2 + alt, 8]] if alt == 0 else [[0, 8, 5], [6, 3, 9]]
	for s in sacs:
		var x: int = s[0]
		var y: int = s[1]
		var sq: int = s[2]
		_r(t, x + sq / 2, y + sq, 1, 14 - y - sq, hi)
		_r(t, x, y, sq, sq, hi)
		_r(t, x + 1, y + 1, sq - 2, sq - 2, inner)
		_r(t, x + 1, y + 1, sq - 2, 1, lite)
		var cr: int = maxi(sq / 3, 2)
		_r(t, x + (sq - cr) / 2, y + (sq - cr) / 2, cr, cr, glow)
	var big: Array = sacs[1]
	_r(t, int(big[0]) + 2, int(big[1]) - 2, 1, 2, hi)
	t.set_pixel(int(big[0]) + 2, maxi(int(big[1]) - 3, 0), glow)


## Трубки глубины: столбики «плоти» разной высоты, кончики тлеют, над ними — споры.
static func _paint_tubes(t: Image, rng: RandomNumberGenerator) -> void:
	var hi: Color = DB.pal("d_hi")
	var glow: Color = DB.pal("d_glow")
	_r(t, 1, 14, 14, 2, hi)
	for k in 4:
		var th: int = 5 + rng.randi_range(0, 7)
		var x: int = 2 + k * 3
		_r(t, x, 14 - th, 2, th, hi.darkened(0.1) if k % 2 == 0 else hi)
		_r(t, x, 14 - th, 2, 1, glow)
		if rng.randf() < 0.6:
			t.set_pixel(x + (k % 2), maxi(14 - th - 2 - rng.randi_range(0, 2), 0), glow)
