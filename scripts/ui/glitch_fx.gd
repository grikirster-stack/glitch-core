class_name GlitchFx
extends CanvasLayer
## Глитч по событию (ADR-003 V7, #108): короткие экранные эффекты — только сигнал угрозы.
##
## Концепт A: живой мир спокоен, глитч чужероден и появляется лишь вокруг угрозы
## («глитч = опасность»). Здесь — экранная часть: короткий всплеск (≤ MAX_SEC),
## строго по событию, никогда постоянно. Всё квадратное и блочное:
##  * релей ловит сигнал — блоки «артефактов сжатия» у излучателя: квадрат
##    2×2 макропикселя (по BLOCK_PX px мира), часть блоков — мозаика со сдвигом,
##    часть подкрашена цветом опасности или свечением спор;
##      этап 2 «релей отзывается», этап 4 «релей запущен» (Game.objective_changed),
##      отметки отсчёта удержания (Game.RELAY_REMINDERS) — «приём сигнала»;
##  * двойник раскрыт (первый раз замер под взглядом) или ударил героя — разрыв
##    строк: полосы ROW_PX px мира сдвигаются вбок, с расслоением каналов;
##  * браун-аут (Game.brownout_changed) — слабый разрыв строк по всему экрану;
##  * телеграф вентиляции (Threat.vent_warning) рядом с героем, на экране — несколько
##    блоков у решётки.
## Дозирование: у каждого события своя пауза (COOLDOWN), слабое событие не перебивает
## сильное (PRIORITY).
##
## Доступность: настройка профиля «Меньше глитча и мерцания» (Profile.less_glitch,
## user://profile.cfg; переключатель в меню — menu_toggle). Флаг — GlitchFx.calm: при
## нём шейдер не включается вовсе, важные события (релей запущен, двойник раскрыт)
## дают спокойную вспышку — ровная полупрозрачная заливка, гаснет плавно, без мерцания.
## Тот же флаг читают фантомы: расслоение силуэта стоит на месте, а не мигает
## (Phantom._split_d). Скобки HUD и эмиссия не мерцают — им флаг не нужен.
##
## Как устроено: один CanvasLayer (LAYER, под HUD — интерфейс остаётся читаемым)
## с одним ColorRect, оба создаются в _ready. В простое ColorRect скрыт (шейдер с
## экранной текстурой не выполняется, копии экрана нет), _process выключен, если
## не за чем следить (двойник на сцене, отсчёт релея) — ни узлов, ни работы в кадре.

## Слой: над миром и туманом, под HUD (UI — 10).
const LAYER: int = 9
## Предел длительности любого эффекта, с.
const MAX_SEC: float = 0.5
## Сторона блока сжатия, px мира: блок — 2×2 макропикселя по BLOCK_PX / 2.
const BLOCK_PX: float = 8.0
## Высота полосы разрыва строк, px мира.
const ROW_PX: float = 4.0
## Как часто перебрасывать узор глитча, с (узор «прыгает», а не течёт).
const STEP_SEC: float = 0.08
## Двойник бьёт героя, если ближе этого, px (Phantom: удар с 22 px).
const STRIKE_PX: float = 34.0
## Событие вне экрана (с этим запасом, px экрана) эффекта не даёт.
const SCREEN_MARGIN: float = 48.0
## Спокойная вспышка: непрозрачность в начале (гаснет линейно до 0).
const CALM_ALPHA: float = 0.14

enum Kind { RELAY_START, RELAY_SIGNAL, DOPPEL_REVEAL, DOPPEL_STRIKE, BROWNOUT, VENT }

## По Kind: длительность, с.
const DURATION: Array[float] = [0.45, 0.3, 0.4, 0.3, 0.35, 0.25]
## Плотность блоков (доля блоков в квадрате при полной силе); 0 — нет блоков.
const BLOCKS: Array[float] = [0.55, 0.4, 0.0, 0.0, 0.0, 0.3]
## Доля сдвинутых полос при полной силе; 0 — нет разрыва строк.
const TEAR: Array[float] = [0.0, 0.0, 0.45, 0.35, 0.16, 0.0]
## Полуразмер области, px мира: квадрат блоков / полоса строк вокруг точки; 0 — весь экран.
const RADIUS: Array[float] = [64.0, 40.0, 72.0, 48.0, 0.0, 24.0]
## Пауза до следующего такого же события, с.
const COOLDOWN: Array[float] = [1.0, 2.0, 1.0, 1.0, 2.0, 3.0]
## Кто кого перебивает: слабое не прерывает идущее сильное.
const PRIORITY: Array[int] = [3, 1, 5, 4, 2, 0]
## Спокойная вспышка при «меньше глитча»: только у важных событий.
const CALM_FLASH: Array[bool] = [true, false, true, false, false, false]
const NAMES: Array[String] = ["relay_start", "relay_signal", "doppel_reveal", "doppel_strike",
		"brownout", "vent"]

## Меньше глитча и мерцания (доступность). Общий флаг: читают и фантомы.
static var calm: bool = false
## Флаг уже взят из профиля (меню или первый запуск сцены).
static var _calm_known: bool = false

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _kind: int = -1
var _left: float = 0.0
var _dur: float = 0.0
var _step: float = 0.0
var _calm_on: bool = false
var _calm_color: Color = Color.WHITE
var _world_at: Vector2 = Vector2.ZERO
var _local: bool = false
var _seed: float = 0.0
var _next_ok: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Двойники на сцене и раскрыт ли уже каждый (параллельные массивы).
var _doppels: Array = []
var _revealed: Array[bool] = []
var _hp_prev: float = -1.0
var _relay_prev: float = -1.0

# ---------------------------------------------- СЧЁТЧИКИ (для сценария и замеров)
## Сколько раз включился шейдер глитча / спокойная вспышка / событие отброшено
## (пауза, приоритет, вне экрана, «меньше глитча» без вспышки).
var stat_fired: int = 0
var stat_calm: int = 0
var stat_skipped: int = 0
## По Kind: сколько раз включался шейдер.
var stat_by_kind: PackedInt32Array = PackedInt32Array()
## Длительность последнего эффекта от включения до выключения, с (по delta кадров).
var stat_last_sec: float = 0.0
var stat_us: int = 0
var stat_frames: int = 0


func _ready() -> void:
	layer = LAYER
	_rng.randomize()
	_next_ok.resize(NAMES.size())
	stat_by_kind.resize(NAMES.size())
	if not _calm_known:
		_calm_known = true
		calm = Profile.read_less_glitch()
	if OS.get_cmdline_user_args().has("--less-glitch"):
		calm = true
	var sh: Shader = Shader.new()
	sh.code = shader_code()
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("danger", DB.pal("danger"))
	_mat.set_shader_parameter("bio", DB.pal("bio"))
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false
	add_child(_rect)
	Game.objective_changed.connect(_on_objective)
	Game.brownout_changed.connect(_on_brownout)
	Threat.vent_warning.connect(_on_vent)
	Threat.phantom_spawned.connect(_on_phantom)
	UI.run_loaded.connect(_wake)
	_wake()


## Эффект сейчас включён (шейдер или спокойная вспышка).
func active() -> bool:
	return _rect != null and _rect.visible


## Идёт именно шейдер глитча (не спокойная вспышка).
func glitch_active() -> bool:
	return active() and not _calm_on


## Вид идущего эффекта ("" — ничего).
func active_name() -> String:
	return NAMES[_kind] if active() and _kind >= 0 else ""


# ------------------------------------------------------------------ СОБЫТИЯ

func _on_objective(stage: int) -> void:
	var bp: Vector2 = World.cell_to_world(World.beacon_cell)
	if stage == 4:
		fire(Kind.RELAY_START, bp)
	elif stage == 2:
		fire(Kind.RELAY_SIGNAL, bp)
	_wake()


func _on_brownout(on: bool) -> void:
	if on:
		fire(Kind.BROWNOUT, Vector2.ZERO)


func _on_vent(cell: Vector2i) -> void:
	fire(Kind.VENT, World.cell_to_world(cell))


func _on_phantom(ph: Node) -> void:
	if ph == null or String(ph.get("kind")) != "doppel" or _doppels.has(ph):
		return
	_doppels.append(ph)
	_revealed.append(false)
	_wake()


## Запустить эффект вида kind в мировой точке at (для браун-аута точка не нужна).
## true — эффект (глитч или спокойная вспышка) включился.
func fire(kind: int, at: Vector2) -> bool:
	if _clock < _next_ok[kind]:
		stat_skipped += 1
		return false
	if active() and PRIORITY[kind] < PRIORITY[_kind]:
		stat_skipped += 1
		return false
	var local: bool = RADIUS[kind] > 0.0
	if local and not _on_screen(at):
		stat_skipped += 1
		return false
	if calm and not CALM_FLASH[kind]:
		stat_skipped += 1
		return false
	_next_ok[kind] = _clock + COOLDOWN[kind]
	_kind = kind
	_dur = minf(DURATION[kind], MAX_SEC)
	_left = _dur
	_world_at = at
	_local = local
	_calm_on = calm
	stat_last_sec = 0.0
	if _calm_on:
		stat_calm += 1
		_calm_color = DB.pal("bio") if kind == Kind.RELAY_START else DB.pal("danger")
		_rect.material = null
	else:
		stat_fired += 1
		stat_by_kind[kind] += 1
		_rect.material = _mat
		_step = 0.0
	_apply()
	_rect.visible = true
	set_process(true)
	return true


## Погасить эффект сразу.
func stop() -> void:
	_left = 0.0
	if _rect != null:
		_rect.visible = false
		_rect.material = null


# ------------------------------------------------------------------ КАДР

func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	stat_frames += 1
	_clock += delta
	if active():
		_left -= delta
		stat_last_sec += delta
		if _left <= 0.0:
			stop()
		else:
			_step -= delta
			_apply()
	_watch()
	if not active() and not _watching():
		set_process(false)
	stat_us += Time.get_ticks_usec() - t0


## Есть ли за чем следить в кадре: двойник на сцене или идёт отсчёт релея.
func _watching() -> bool:
	return not _doppels.is_empty() or Game.relay_active


## Включить _process, если есть за чем следить (после загрузки забега, новых событий).
func _wake() -> void:
	_relay_prev = Game.relay_timer if Game.relay_active else -1.0
	if active() or _watching():
		set_process(true)
	else:
		set_process(false)


## Слежка за двойниками (раскрытие, удар) и за отметками отсчёта релея.
func _watch() -> void:
	if not _doppels.is_empty():
		var hero: Node2D = Game.player as Node2D
		var hp: float = float(hero.get("hp")) if hero != null and is_instance_valid(hero) else -1.0
		var hurt: bool = _hp_prev >= 0.0 and hp >= 0.0 and hp < _hp_prev
		_hp_prev = hp
		for i in range(_doppels.size() - 1, -1, -1):
			var d: Node2D = _doppels[i] as Node2D if is_instance_valid(_doppels[i]) else null
			if d == null or not bool(d.get("alive")):
				_doppels.remove_at(i)
				_revealed.remove_at(i)
				continue
			if not _revealed[i] and bool(d.get("frozen")):
				_revealed[i] = true
				fire(Kind.DOPPEL_REVEAL, d.global_position)
			elif hurt and hero.global_position.distance_to(d.global_position) < STRIKE_PX:
				hurt = false
				fire(Kind.DOPPEL_STRIKE, d.global_position)
		if _doppels.is_empty():
			_hp_prev = -1.0
	if Game.relay_active:
		var t: float = Game.relay_timer
		if _relay_prev >= 0.0:
			for r in Game.RELAY_REMINDERS:
				if _relay_prev > float(r) and t <= float(r):
					fire(Kind.RELAY_SIGNAL, World.cell_to_world(World.beacon_cell))
		_relay_prev = t
	else:
		_relay_prev = -1.0


## Параметры кадра: сила (линейно гаснет), узор, точка на экране.
func _apply() -> void:
	var k: float = clampf(_left / maxf(_dur, 0.001), 0.0, 1.0)
	if _calm_on:
		_rect.color = Color(_calm_color, CALM_ALPHA * k)
		return
	_rect.color = Color.WHITE
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var px: float = maxf(ct.get_scale().x, 0.5)
	if _step <= 0.0:
		_step = STEP_SEC
		_seed = float(_rng.randi_range(1, 9999))
	_mat.set_shader_parameter("rect_size", get_viewport().get_visible_rect().size)
	_mat.set_shader_parameter("px", px)
	_mat.set_shader_parameter("strength", k)
	_mat.set_shader_parameter("seed", _seed)
	_mat.set_shader_parameter("blocks", BLOCKS[_kind])
	_mat.set_shader_parameter("tear", TEAR[_kind])
	_mat.set_shader_parameter("center", ct * _world_at if _local else Vector2.ZERO)
	_mat.set_shader_parameter("radius", RADIUS[_kind] * px if _local else 0.0)


## Мировая точка на экране (с запасом SCREEN_MARGIN)?
func _on_screen(at: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var p: Vector2 = get_viewport().get_canvas_transform() * at
	return get_viewport().get_visible_rect().grow(SCREEN_MARGIN).has_point(p)


# ------------------------------------------------------------------ НАСТРОЙКА

## Переключатель «Меньше глитча и мерцания» для меню: настраивает данную кнопку
## (её создаёт меню — в своей теме), пишет выбор в профиль и в GlitchFx.calm.
static func menu_toggle(btn: Button, p: Profile, path: String) -> Button:
	set_calm(p.less_glitch)
	btn.toggle_mode = true
	btn.button_pressed = p.less_glitch
	btn.text = _toggle_text(p.less_glitch)
	btn.tooltip_text = "Без экранных глитч-эффектов; фантомы не мерцают"
	btn.toggled.connect(func(on: bool) -> void:
			btn.text = _toggle_text(on)
			p.less_glitch = on
			p.save_to(path)
			set_calm(on))
	return btn


static func _toggle_text(on: bool) -> String:
	return "Меньше глитча и мерцания: " + ("да" if on else "нет")


static func set_calm(on: bool) -> void:
	calm = on
	_calm_known = true


# ------------------------------------------------------------------ ШЕЙДЕР
## Всё в px экрана (UV × rect_size); px — размер пикселя мира на экране (зум камеры).
## Блоки: квадрат на сетке блоков (расстояние Чебышёва) вокруг center; блок
## выбран по хешу с вероятностью strength·blocks — мозаика 2×2 со сдвигом на блок,
## часть — подкрашена. Разрыв строк: полоса выбрана с вероятностью strength·tear,
## сдвиг кратен 2 px мира, каналы R/B разведены на 1 px мира. Невыбранный
## пиксель прозрачен — под ним обычный кадр.
static func shader_code() -> String:
	return """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float px = 2.2;
uniform float strength = 0.0;
uniform float seed = 1.0;
uniform float blocks = 0.0;
uniform float tear = 0.0;
uniform vec2 center = vec2(0.0);
uniform float radius = 0.0;
uniform vec4 danger : source_color = vec4(0.94, 0.19, 0.42, 1.0);
uniform vec4 bio : source_color = vec4(0.50, 0.90, 0.82, 1.0);

const float BLOCK = %.1f;
const float ROW = %.1f;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 0.731) * 43758.5453);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec4 outc = vec4(0.0);
	if (blocks > 0.0) {
		float bs = BLOCK * px;
		vec2 b = floor(p / bs);
		vec2 cb = floor(center / bs);
		float far = max(abs(b.x - cb.x), abs(b.y - cb.y)) * bs;
		if ((radius <= 0.0 || far <= radius) && h(b) < strength * blocks) {
			float sb = bs * 0.5;
			vec2 src = (floor(p / sb) + 0.5) * sb;
			src.x += (floor(h(b + 3.1) * 3.0) - 1.0) * bs;
			vec4 c = texture(screen_tex, SCREEN_UV + (src - p) / rect_size);
			float r = h(b + 7.7);
			if (r < 0.3) {
				c.rgb = mix(c.rgb, danger.rgb, 0.55);
			} else if (r < 0.55) {
				c.rgb = mix(c.rgb, bio.rgb, 0.45);
			}
			outc = vec4(c.rgb, 1.0);
		}
	}
	if (tear > 0.0) {
		float rh = ROW * px;
		float row = floor(p.y / rh);
		float near = abs(row - floor(center.y / rh)) * rh;
		if ((radius <= 0.0 || near <= radius) && h(vec2(row, 1.0)) < strength * tear) {
			float shift = (floor(h(vec2(row, 2.0)) * 9.0) - 4.0) * 2.0 * px;
			vec2 o = vec2(shift, 0.0) / rect_size;
			vec2 ch = vec2(px, 0.0) / rect_size;
			vec4 g = texture(screen_tex, SCREEN_UV + o);
			float rr = texture(screen_tex, SCREEN_UV + o + ch).r;
			float bb = texture(screen_tex, SCREEN_UV + o - ch).b;
			outc = vec4(rr, g.g, bb, 1.0);
		}
	}
	COLOR = outc;
}
""" % [BLOCK_PX, ROW_PX]
