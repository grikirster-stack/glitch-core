class_name Profile
extends RefCounted
## Профиль игрока (ADR-002 § 3 D8, § 4.6; MP-B, #87): ник, uid и параметры вида.
##
## Файл user://profile.cfg (ConfigFile):
##   [profile] uid  — случайные 64 бита, создаются один раз (по нему хост узнаёт
##                    вернувшегося игрока);
##             nick — ник (правила — nick_error());
##             look — параметры вида, Look (u16: 4 части по 4 бита);
##   [net]     recent_ips — последние адреса «Подключиться по IP» (MP-H, #93);
##             port       — порт игры.
##
## Чужой или битый файл не валит игру: неверный ник и тип поля — значение по
## умолчанию, uid 0 — новый uid. Неизвестные индексы вида хранятся как есть,
## рисуются как 0 (Avatar.resolve).
##
## Profile.session — выбор главного меню на этот запуск процесса («Одиночная
## игра»: аргументы старта и вид). main.gd читает его вместо командной строки;
## пустой — меню не открывалось.

const PATH: String = "user://profile.cfg"
## Ник по умолчанию (валиден по nick_error()).
const DEFAULT_NICK: String = "Инженер"
const NICK_MIN: int = 2
const NICK_MAX: int = 16
## Порт игры по умолчанию (ADR-002 § 4.1; то же число, что у Net, MP-A).
const DEFAULT_PORT: int = 24642
## Сколько адресов помнит «Подключиться по IP».
const RECENT_IPS_MAX: int = 8

## Выбор меню на этот запуск: {"args": PackedStringArray, "look": int}. См. шапку.
static var session: Dictionary = {}

var uid: int = 0
var nick: String = DEFAULT_NICK
var look: int = 0
var recent_ips: PackedStringArray = PackedStringArray()
var port: int = DEFAULT_PORT


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

## Почему ник не годится ("" — годится). Проверяется ник после strip_edges():
## 2–16 символов; буквы A–Z a–z А–Я а–я Ё ё, цифры, пробел, «_ - .»; первый и
## последний — буква или цифра; двух пробелов подряд нет.
static func nick_error(raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.length() < NICK_MIN:
		return "Ник — хотя бы %d символа" % NICK_MIN
	if s.length() > NICK_MAX:
		return "Ник — не длиннее %d символов" % NICK_MAX
	for i in s.length():
		if not _nick_char(s.unicode_at(i)):
			return "Нельзя символ «%s»: только буквы, цифры, пробел, _ - ." % s[i]
	if not _alnum(s.unicode_at(0)) or not _alnum(s.unicode_at(s.length() - 1)):
		return "Ник начинается и кончается буквой или цифрой"
	if s.contains("  "):
		return "Два пробела подряд нельзя"
	return ""


static func is_valid_nick(raw: String) -> bool:
	return nick_error(raw) == ""


static func _alnum(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) \
			or (c >= 0x30 and c <= 0x39) \
			or (c >= 0x410 and c <= 0x44F) or c == 0x401 or c == 0x451


static func _nick_char(c: int) -> bool:
	return _alnum(c) or c == 0x20 or c == 0x5F or c == 0x2D or c == 0x2E


# ------------------------------------------------------------------ ФАЙЛ

## Профиль из файла; нет файла или нет uid — создаёт и сразу записывает
## (uid появляется один раз). path — для тестов (временный путь).
static func load_or_create(path: String = PATH) -> Profile:
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
	if p.uid == 0:
		p.uid = new_uid()
		dirty = true
	if dirty:
		p.save_to(path)
	return p


func save_to(path: String = PATH) -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("profile", "uid", uid)
	cfg.set_value("profile", "nick", nick)
	cfg.set_value("profile", "look", look & 0xFFFF)
	cfg.set_value("net", "recent_ips", recent_ips)
	cfg.set_value("net", "port", port)
	return cfg.save(path)


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
