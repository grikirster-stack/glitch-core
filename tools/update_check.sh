#!/usr/bin/env bash
# Проверка, есть ли на origin/main коммиты новее локальных.
# Только чтение: fetch обновляет remote-tracking, дерево и HEAD не двигает.
# Не мержит, не тянет, не чистит, Godot не вызывает, сейвы не трогает.
# Лаунчер (его ещё нет) ветвится по коду возврата, не разбирая текст.

set -u

OFFICIAL_HTTPS="https://github.com/grikirster-stack/glitch-core"
OFFICIAL_SSH="git@github.com:grikirster-stack/glitch-core"
FETCH_TIMEOUT=10

offline=0
if [[ "${1:-}" == "--offline" ]]; then
	offline=1
elif [[ -n "${1:-}" ]]; then
	echo "неизвестный аргумент: $1" >&2
	echo "использование: tools/update_check.sh [--offline]" >&2
	exit 3
fi

# Корень репозитория, даже если скрипт вызвали не из него.
root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
	echo "это не git-репозиторий" >&2
	exit 3
}
cd "$root" || exit 3

origin="$(git remote get-url origin 2>/dev/null)" || origin=""
# Хвост .git у HTTPS не делает remote чужим.
origin_norm="${origin%.git}"

echo "origin: ${origin:-нет}"

if [[ "$origin_norm" != "$OFFICIAL_HTTPS" && "$origin" != "$OFFICIAL_SSH" && "$origin" != "${OFFICIAL_SSH}.git" ]]; then
	echo "ветка: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo неизвестно)"
	echo "состояние: отказ, remote не официальный"
	echo "действие не выполнялось (только проверка)"
	exit 3
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo неизвестно)"
local_full="$(git rev-parse HEAD 2>/dev/null || echo "")"
local_short="$(git rev-parse --short HEAD 2>/dev/null || echo неизвестно)"

fetch_note=""
if [[ "$offline" -eq 1 ]]; then
	fetch_note="fetch: пропущен"
else
	# timeout из coreutils: fetch не должен висеть на мёртвой сети.
	# Ошибку сети глотаем: офлайн неотличим от «обновлений нет», кроме строки состояния.
	if ! fetch_out="$(timeout "$FETCH_TIMEOUT" git fetch origin main 2>&1)"; then
		# timeout (124) и коды git (128+) — офлайн: remote уже проверен выше.
		# Вывод fetch не печатаем: лаунчер разбирает только наши строки.
		fetch_note="fetch: не удался (офлайн)"
	fi
fi

# rev-parse без --verify при несуществующей ref печатает имя и всё равно падает.
# Пустая строка — ref ещё не приезжала, это не хеш.
origin_full="$(git rev-parse --verify origin/main 2>/dev/null || true)"
if [[ -n "$origin_full" ]]; then
	origin_short="$(git rev-parse --short origin/main 2>/dev/null || echo неизвестно)"
else
	origin_short="неизвестно"
fi

# Сравнение с уже известным origin/main. После неудачного fetch это снимок
# до попытки, не свежие данные — тогда состояние честно «неизвестно (офлайн)».
# --offline просит именно это сравнение и не прячет его за «неизвестно».
state="неизвестно (офлайн)"
code=0
# Признак неудачи fetch — строка «не удался», а не флаг --offline.
# --offline сравнивает HEAD с уже известным origin/main и состояние не прячет.
fetch_failed=0
if [[ "${fetch_note:-}" == "fetch: не удался (офлайн)" ]]; then
	fetch_failed=1
fi

if [[ -z "$origin_full" ]]; then
	# origin/main ещё не приезжал — сравнивать не с чем, это не расхождение.
	state="неизвестно (офлайн)"
	code=0
elif [[ -n "$local_full" && "$fetch_failed" -eq 0 ]]; then
	if [[ "$local_full" == "$origin_full" ]]; then
		state="актуально"
		code=0
	elif git merge-base --is-ancestor "$local_full" "$origin_full" 2>/dev/null; then
		ahead="$(git rev-list --count "${local_full}..${origin_full}" 2>/dev/null || echo "?")"
		state="origin/main впереди на ${ahead} коммитов"
		code=2
	elif git merge-base --is-ancestor "$origin_full" "$local_full" 2>/dev/null; then
		behind="$(git rev-list --count "${origin_full}..${local_full}" 2>/dev/null || echo "?")"
		state="локально впереди на ${behind} коммитов"
		code=0
	else
		state="ветки разошлись"
		code=0
	fi
fi

dirty="$(git status --porcelain 2>/dev/null || true)"
if [[ -n "$dirty" ]]; then
	tree="грязное"
	# Грязное дерево важнее: лаунчер не должен думать, что можно применять.
	code=3
else
	tree="чистое"
fi

echo "ветка: $branch"
echo "локально: $local_short"
echo "origin/main: $origin_short"
if [[ -n "$fetch_note" ]]; then
	echo "$fetch_note"
fi
echo "состояние: $state"
echo "дерево: $tree"
echo "действие не выполнялось (только проверка)"
exit "$code"
