class_name UpdateCheck
## Тихая проверка нового релиза (#300). Только чистые функции: сеть и меню —
## в main_menu.gd. Ничего не качает и не пишет в файлы.
##
## GitHub Releases отдаёт `tag_name` вида vX.Y.Z и ссылки на github.com.
## Черновик, пререлиз и чужой адрес отбрасываются целиком.

const RELEASES_URL: String = "https://api.github.com/repos/grikirster-stack/glitch-core/releases/latest"
const APK_SUFFIX: String = "-android.apk"


## JSON последнего релиза → {tag, html_url, apk_url}. {} при любой проблеме.
static func parse_release(json_text: String) -> Dictionary:
	var text: String = json_text.strip_edges()
	if not text.begins_with("{"):
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if bool(data.get("draft", false)) or bool(data.get("prerelease", false)):
		return {}
	var tag: String = _version_of(str(data.get("tag_name", "")))
	if tag == "":
		return {}
	var html_url: String = str(data.get("html_url", ""))
	if not _is_github_https(html_url):
		return {}
	var apk_url: String = ""
	var assets: Variant = data.get("assets", [])
	if typeof(assets) == TYPE_ARRAY:
		for raw in assets:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var asset: Dictionary = raw
			if not str(asset.get("name", "")).ends_with(APK_SUFFIX):
				continue
			var url: String = str(asset.get("browser_download_url", ""))
			if _is_github_https(url):
				apk_url = url
			break
	return {"tag": tag, "html_url": html_url, "apk_url": apk_url}


## tag новее current. «dev», пусто и мусор — не новее. 0.6.10 > 0.6.9.
static func is_newer(current: String, tag: String) -> bool:
	var a: PackedInt32Array = _parts(current)
	var b: PackedInt32Array = _parts(tag)
	if a.is_empty() or b.is_empty():
		return false
	for i in 3:
		if b[i] != a[i]:
			return b[i] > a[i]
	return false


## Релизную сборку с окном имеет смысл спросить. Headless и «dev» — нет.
static func should_check(version: String, headless: bool) -> bool:
	if headless:
		return false
	return not _parts(version).is_empty()


## «v1.2.3» / «1.2.3» → «1.2.3»; иначе пусто. Лишние куски (v1.2.3-rc) — не тег.
static func _version_of(raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	if _parts(s).is_empty():
		return ""
	return s


static func _parts(raw: String) -> PackedInt32Array:
	var s: String = raw.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var bits: PackedStringArray = s.split(".")
	if bits.size() != 3:
		return PackedInt32Array()
	var out: PackedInt32Array = PackedInt32Array()
	for bit in bits:
		if bit == "" or not bit.is_valid_int():
			return PackedInt32Array()
		if bit.length() > 1 and bit.begins_with("0"):
			return PackedInt32Array()
		out.append(int(bit))
	return out


## Только https и хост github.com: иначе ссылку не открываем.
static func _is_github_https(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var rest: String = url.substr(8)
	var slash: int = rest.find("/")
	var host: String = rest if slash < 0 else rest.substr(0, slash)
	var at: int = host.rfind("@")
	if at >= 0:
		host = host.substr(at + 1)
	var colon: int = host.find(":")
	if colon >= 0:
		host = host.substr(0, colon)
	return host == "github.com"
