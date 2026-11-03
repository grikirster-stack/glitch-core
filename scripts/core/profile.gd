class_name Profile
extends RefCounted
## Профиль игрока (ADR-002 § 3 D8, § 4.6; MP-B, #87): ник, uid и параметры вида.
##
## Файл user://profile.cfg (ConfigFile; в тестовом прогоне — свой файл процесса,
## default_path(), #132):
##   [profile] uid  — случайные 64 бита, создаются один раз (по нему хост узнаёт
##                    вернувшегося игрока);
##             nick — ник (правила — nick_error());
##             look — параметры вида, Look (u16: 4 части по 4 бита);
##   [net]     recent_ips — последние адреса «Подключиться по IP» (MP-H, #93);
##             port       — порт игры;
##   [access]  less_glitch — «Меньше глитча и мерцания» (ADR-003 V7, #108): GlitchFx.calm.
##
## Чужой или битый файл не валит игру: неверный ник и тип поля — значение по
## умолчанию, uid 0 — новый uid. Неизвестные индексы вида хранятся как есть,
## рисуются как 0 (Avatar.resolve).
##
## Правила ника — одни на игру: Net.nick_error() (их же проверяет хост в
## рукопожатии). Меню кладёт профиль в Net.local_profile (to_net()).

## Скрипт автозагрузки Net: его статические функции и константы. По имени
## автозагрузки не обращаемся — Profile грузят и инструменты в режиме --script.
const NetScript = preload("res://scripts/autoload/net.gd")

const PATH: String = "user://profile.cfg"
## Ник по умолчанию (как у Net).
const DEFAULT_NICK: String = NetScript.DEFAULT_NICK
## Порт игры по умолчанию.
const DEFAULT_PORT: int = NetScript.GAME_PORT
## Сколько адресов помнит «Подключиться по IP».
const RECENT_IPS_MAX: int = 8

var uid: int = 0
var nick: String = DEFAULT_NICK
var look: int = 0
var recent_ips: PackedStringArray = PackedStringArray()
var port: int = DEFAULT_PORT
## Меньше глитча и мерцания (доступность, ADR-003 V7): читает GlitchFx.
var less_glitch: bool = false
## Пройденные главы кампании (id из Campaign.CHAPTERS, ADR-004).
var campaign_done: PackedStringArray = PackedStringArray()


## Параметры вида: 4 индекса по 4 бита в одном u16 (в сети — как есть).
## Биты 0–3 — цвет скафандра, 4–7 — шлем/визор, 8–11 — аксессуар,
## 12–15 — рюкзак/баллоны. Что значит каждый индекс, решает Avatar.
class Look:
	const COLOR: int = 0
	const HELMET: int = 1
	const ACCESSORY: int = 2
	const PACK: int = 3
	const PARTS: int = 4
	const BITS: int = 4
	## Индексов на часть (0..15).
	const SIZE: int = 1 << BITS
	const MASK: int = SIZE - 1
	## Подписи частей для меню.
	const NAMES: Array = ["Цвет скафандра", "Шлем / визор", "Аксессуар", "Рюкзак"]

	## Четыре индекса → u16. Лишние биты индексов отбрасываются.
	static func pack(parts: PackedInt32Array) -> int:
		var v: int = 0
		for i in mini(parts.size(), PARTS):
			v |= (parts[i] & MASK) << (i * BITS)
		return v

	## u16 → четыре индекса.
	static func unpack(v: int) -> PackedInt32Array:
		var out: PackedInt32Array = PackedInt32Array()
		out.resize(PARTS)
		for i in PARTS:
			out[i] = part(v, i)
		return out

	static func part(v: int, i: int) -> int:
		return (v >> (i * BITS)) & MASK

	## Тот же вид с другим индексом части i.
	static func with_part(v: int, i: int, idx: int) -> int:
		var shift: int = i * BITS
		return ((v & 0xFFFF) & ~(MASK << shift)) | ((idx & MASK) << shift)


# ------------------------------------------------------------------ НИК

## Годится ли ник (правила — Net.nick_error()).
static func is_valid_nick(raw: String) -> bool:
	return NetScript.nick_error(raw) == ""


## Профиль для рукопожатия: Net.local_profile = profile.to_net().
func to_net() -> Dictionary:
	return {"uid": uid, "nick": nick, "look": look & 0xFFFF}


# ------------------------------------------------------------------ ФАЙЛ

## Профиль по умолчанию: user://profile.cfg; в тестовом прогоне (TestEnv) — свой
## файл процесса profile~t<pid>.cfg.
static func default_path() -> String:
	return TestEnv.file(PATH) if TestEnv.active() else PATH


## Профиль из файла; нет файла или нет uid — создаёт и сразу записывает
## (uid появляется один раз). path — для тестов (временный путь); пусто — default_path().
static func load_or_create(path: String = "") -> Profile:
	if path == "":
		path = default_path()
	var p: Profile = Profile.new()
	var cfg: ConfigFile = ConfigFile.new()
	var dirty: bool = cfg.load(path) != OK
	var v_uid: Variant = cfg.get_value("profile", "uid", 0)
	p.uid = int(v_uid) if v_uid is int else 0
	var v_nick: Variant = cfg.get_value("profile", "nick", DEFAULT_NICK)
	p.nick = String(v_nick).strip_edges() if v_nick is String else DEFAULT_NICK
	if not is_valid_nick(p.nick):
		p.nick = DEFAULT_NICK
		dirty = true
	var v_look: Variant = cfg.get_value("profile", "look", 0)
	p.look = (int(v_look) & 0xFFFF) if v_look is int else 0
	var v_ips: Variant = cfg.get_value("net", "recent_ips", PackedStringArray())
	if v_ips is PackedStringArray or v_ips is Array:
		for ip in v_ips:
			if ip is String and p.recent_ips.size() < RECENT_IPS_MAX:
				p.recent_ips.append(ip)
	var v_port: Variant = cfg.get_value("net", "port", DEFAULT_PORT)
	p.port = int(v_port) if v_port is int and int(v_port) > 0 and int(v_port) < 65536 \
			else DEFAULT_PORT
	var v_lg: Variant = cfg.get_value("access", "less_glitch", false)
	p.less_glitch = v_lg if v_lg is bool else false
	var v_done: Variant = cfg.get_value("campaign", "done", PackedStringArray())
	if v_done is PackedStringArray or v_done is Array:
		for c in v_done:
			if c is String and not p.campaign_done.has(c):
				p.campaign_done.append(c)
	if p.uid == 0:
		p.uid = new_uid()
		dirty = true
	if dirty:
		p.save_to(path)
	return p


func save_to(path: String = "") -> Error:
	if path == "":
		path = default_path()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("profile", "uid", uid)
	cfg.set_value("profile", "nick", nick)
	cfg.set_value("profile", "look", look & 0xFFFF)
	cfg.set_value("net", "recent_ips", recent_ips)
	cfg.set_value("net", "port", port)
	cfg.set_value("access", "less_glitch", less_glitch)
	# Главы отмечает и сама игра (Campaign.mark_done) — свой экземпляр, загруженный раньше
	# (меню, пауза), не должен стереть отметку: в файл — объединение.
	var old: ConfigFile = ConfigFile.new()
	if old.load(path) == OK:
		var v_done: Variant = old.get_value("campaign", "done", PackedStringArray())
		if v_done is PackedStringArray or v_done is Array:
			for c in v_done:
				if c is String and not campaign_done.has(c):
					campaign_done.append(c)
	cfg.set_value("campaign", "done", campaign_done)
	return cfg.save(path)


## «Меньше глитча» из файла, не создавая профиль (игра запущена без меню: --test,
## --scenario, сеть). Нет файла или битое поле — false.
## В тестовом прогоне по умолчанию — файл теста (нет — false): итог не зависит от
## настроек игрока.
static func read_less_glitch(path: String = "") -> bool:
	if path == "":
		path = default_path()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	var v: Variant = cfg.get_value("access", "less_glitch", false)
	return v if v is bool else false


## «Подключиться по IP» (MP-H, #93): адрес — в начало списка последних, без повторов,
## не больше RECENT_IPS_MAX.
func remember_ip(addr: String) -> void:
	var a: String = addr.strip_edges()
	if a == "":
		return
	var out: PackedStringArray = PackedStringArray([a])
	for ip in recent_ips:
		if ip != a and out.size() < RECENT_IPS_MAX:
			out.append(ip)
	recent_ips = out


## Случайные 64 бита, не 0. Свой генератор: общий randi() не трогаем.
static func new_uid() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var v: int = 0
	while v == 0:
		v = (int(rng.randi()) << 32) | int(rng.randi())
	return v


## Номер версии для меню: application/config/version (пишет релиз, #80) или "dev".
static func build_version() -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "dev"
