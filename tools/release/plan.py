#!/usr/bin/env python3
"""План релиза (issue #80): следующая версия и русские заметки «что сделано».

Запускается из .github/workflows/release.yml, но работает и локально
(нужны git с полной историей и тегами и авторизованный gh):

    python3 tools/release/plan.py --bump auto --notes .tools/release_notes.md

Что делает:
  1. Находит последний достижимый из HEAD тег vX.Y.Z (нет тегов — база 0.0.0).
  2. Собирает PR, смерженные в main после этого тега: PR попадает в список, если
     его merge-коммит лежит на first-parent-линии main в диапазоне «тег..HEAD».
  3. Метки PR = метки самого PR + метки issue, которые он закрывает («Closes #N»):
     в проекте метки обычно стоят на issue, а не на PR.
  4. Версия: bump=auto → minor, если у какого-либо PR есть метка gameplay или
     enhancement, иначе patch. Без тегов первая версия — 0.1.0 (major → 1.0.0).
  5. Android versionCode = X*10000 + Y*100 + Z — растёт монотонно при Y, Z < 100.

Результат: ключи version, tag, prev_tag, code, prs, commits в $GITHUB_OUTPUT
(или в stdout) и markdown-заметки в файл --notes.
"""

import argparse
import json
import os
import re
import subprocess
import sys

TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
MINOR_LABELS = {"gameplay", "enhancement"}
FIX_LABELS = {"bug"}

PR_QUERY = """
query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: MERGED, baseRefName: "main", first: 100, after: $after,
                 orderBy: {field: CREATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        url
        mergeCommit { oid }
        labels(first: 30) { nodes { name } }
        closingIssuesReferences(first: 10) {
          nodes { number labels(first: 30) { nodes { name } } }
        }
      }
    }
  }
}
"""


def run(cmd):
	return subprocess.run(cmd, check=True, capture_output=True, text=True,
			encoding="utf-8").stdout.strip()


def last_tag():
	"""Последний тег vX.Y.Z, достижимый из HEAD, или None."""
	try:
		out = run(["git", "tag", "--merged", "HEAD", "--list", "v*"])
	except subprocess.CalledProcessError:
		return None
	best = None
	for t in out.splitlines():
		m = TAG_RE.match(t.strip())
		if m:
			v = tuple(int(x) for x in m.groups())
			if best is None or v > best[0]:
				best = (v, t.strip())
	return best


def first_parent_commits(prev_tag):
	rng = "HEAD" if prev_tag is None else "%s..HEAD" % prev_tag
	out = run(["git", "log", "--first-parent", "--format=%H", rng])
	return [line for line in out.splitlines() if line]


def fetch_merged_prs(repo):
	owner, name = repo.split("/", 1)
	prs = []
	after = None
	while True:
		cmd = ["gh", "api", "graphql", "-f", "query=" + PR_QUERY,
				"-F", "owner=" + owner, "-F", "name=" + name]
		if after:
			cmd += ["-F", "after=" + after]
		data = json.loads(run(cmd))
		page = data["data"]["repository"]["pullRequests"]
		prs.extend(page["nodes"])
		if not page["pageInfo"]["hasNextPage"]:
			break
		after = page["pageInfo"]["endCursor"]
	return prs


def labels_of(pr):
	names = {n["name"] for n in pr["labels"]["nodes"]}
	for issue in pr["closingIssuesReferences"]["nodes"]:
		names.update(n["name"] for n in issue["labels"]["nodes"])
	return names


def next_version(base, has_tag, bump, prs):
	if bump == "auto":
		bump = "minor" if any(labels_of(p) & MINOR_LABELS for p in prs) else "patch"
	x, y, z = base
	if not has_tag:
		return ((1, 0, 0) if bump == "major" else (0, 1, 0)), bump
	if bump == "major":
		return (x + 1, 0, 0), bump
	if bump == "minor":
		return (x, y + 1, 0), bump
	return (x, y, z + 1), bump


def notes_markdown(repo, server, version, tag, prev_tag, prs, commits, bump):
	groups = {"game": [], "fix": [], "other": []}
	for p in sorted(prs, key=lambda p: p["number"]):
		labels = labels_of(p)
		if labels & FIX_LABELS:
			key = "fix"
		elif labels & MINOR_LABELS:
			key = "game"
		else:
			key = "other"
		groups[key].append("- %s (#%d)" % (p["title"].strip(), p["number"]))

	base_url = "%s/%s" % (server, repo)
	lines = ["## ГЛИТЧ-КОРЕ %s" % tag, ""]
	if prev_tag:
		lines.append("Изменения с %s: %d PR, %d коммитов в main (повышение: %s)."
				% (prev_tag, len(prs), len(commits), bump))
	else:
		lines.append("Первый релиз: %d PR, %d коммитов в main." % (len(prs), len(commits)))
	lines.append("")
	titles = [("game", "Геймплей и новое"), ("fix", "Исправления"), ("other", "Прочее")]
	for key, title in titles:
		if groups[key]:
			lines += ["### " + title, ""] + groups[key] + [""]
	if not prs:
		lines += ["Смерженных PR нет — только прямые коммиты в main.", ""]
	if prev_tag:
		lines.append("Полный diff: %s/compare/%s...%s" % (base_url, prev_tag, tag))
	else:
		lines.append("Полная история: %s/commits/%s" % (base_url, tag))
	lines += [
		"",
		"### Файлы",
		"",
		"- `glitch-core-%s-android.apk` — Android, универсальный APK "
		"(arm64-v8a, armeabi-v7a, x86_64)" % tag,
		"- `glitch-core-%s-windows-x86_64.zip` — Windows" % tag,
		"- `glitch-core-%s-linux-x86_64.zip` — Linux" % tag,
		"",
		"Как поставить APK на телефон — README, раздел «Скачать / Android»: "
		"%s#скачать--android" % base_url,
		"",
	]
	return "\n".join(lines)


def main():
	ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	ap.add_argument("--bump", choices=["auto", "patch", "minor", "major"], default="auto")
	ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "grikirster-stack/glitch-core"))
	ap.add_argument("--server", default=os.environ.get("GITHUB_SERVER_URL", "https://github.com"))
	ap.add_argument("--notes", required=True, help="куда записать заметки (markdown)")
	args = ap.parse_args()

	tag_info = last_tag()
	prev_tag = tag_info[1] if tag_info else None
	base = tag_info[0] if tag_info else (0, 0, 0)

	commits = first_parent_commits(prev_tag)
	in_range = set(commits)
	prs = [p for p in fetch_merged_prs(args.repo)
			if p.get("mergeCommit") and p["mergeCommit"]["oid"] in in_range]

	ver, bump = next_version(base, tag_info is not None, args.bump, prs)
	x, y, z = ver
	if y >= 100 or z >= 100:
		sys.exit("minor/patch >= 100 ломают versionCode X*10000+Y*100+Z — поднимите major")
	version = "%d.%d.%d" % ver
	tag = "v" + version
	code = x * 10000 + y * 100 + z

	notes = notes_markdown(args.repo, args.server, version, tag, prev_tag, prs, commits, bump)
	os.makedirs(os.path.dirname(os.path.abspath(args.notes)), exist_ok=True)
	with open(args.notes, "w", encoding="utf-8") as f:
		f.write(notes)

	out = {
		"version": version,
		"tag": tag,
		"prev_tag": prev_tag or "",
		"code": str(code),
		"bump": bump,
		"prs": str(len(prs)),
		"commits": str(len(commits)),
	}
	text = "".join("%s=%s\n" % kv for kv in out.items())
	gh_out = os.environ.get("GITHUB_OUTPUT")
	if gh_out:
		with open(gh_out, "a", encoding="utf-8") as f:
			f.write(text)
	sys.stdout.write(text)


if __name__ == "__main__":
	main()
