#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 清理旧固件：只保留最近 N 天的 Release（连 tag 一起删），
# 并额外保证每种配置至少留下最新 KEEP_LATEST 个，避免长期编译失败时把固件清空。
#
# 环境变量：
#   KEEP_DAYS    保留天数，默认 7
#   KEEP_LATEST  每种配置至少保留的最新数量，默认 1
#   DRY_RUN      true 时只打印不删除
#   REPO         仓库，默认 $GITHUB_REPOSITORY
#   GH_TOKEN     token，默认 $GITHUB_TOKEN
#
# 用法: KEEP_DAYS=7 bash .github/scripts/prune-releases.sh

set -euo pipefail

KEEP_DAYS=${KEEP_DAYS:-7}
KEEP_LATEST=${KEEP_LATEST:-1}
DRY_RUN=${DRY_RUN:-false}
REPO=${REPO:-${GITHUB_REPOSITORY:-}}
TOKEN=${GH_TOKEN:-${GITHUB_TOKEN:-}}

if [ -z "$REPO" ]; then
	echo "REPO 未设置（可用 GITHUB_REPOSITORY 或 REPO 指定）" >&2
	exit 1
fi
if [ -z "$TOKEN" ]; then
	echo "缺少 token（可用 GITHUB_TOKEN 或 GH_TOKEN 指定）" >&2
	exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	echo "需要 python3 解析 JSON" >&2
	exit 1
fi

API="https://api.github.com/repos/$REPO"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

api() {
	curl -fsSL \
		-H "Authorization: Bearer $TOKEN" \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"$@"
}

echo "仓库: $REPO"
echo "保留策略: 最近 $KEEP_DAYS 天 + 每种配置最新 $KEEP_LATEST 个"
if [ "$DRY_RUN" = "true" ]; then
	echo "模式: DRY RUN（不删除）"
fi

# 先完整收集所有 Release，再统一删除；边翻页边删会漏项
: >"$WORK/all.tsv"
page=1
while [ "$page" -le 50 ]; do
	if ! api "$API/releases?per_page=100&page=$page" >"$WORK/page.json"; then
		echo "拉取第 $page 页 Release 失败" >&2
		exit 1
	fi
	rows=$(python3 - "$WORK/page.json" <<'PY'
import datetime
import json
import re
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    releases = json.load(f)

for rel in releases:
    stamp = rel.get('published_at') or rel.get('created_at')
    epoch = int(datetime.datetime.fromisoformat(
        stamp.replace('Z', '+00:00')).timestamp())
    # tag 形如 CONFIG-SOURCE-BRANCH-YY.MM.DD-HH.MM.SS，去掉结尾时间戳得到配置前缀
    prefix = re.sub(r'-\d{2}\.\d{2}\.\d{2}-\d{2}\.\d{2}\.\d{2}$', '', rel['tag_name'])
    print('\t'.join((str(rel['id']), str(epoch), prefix, rel['tag_name'])))
PY
)
	[ -z "$rows" ] && break
	printf '%s\n' "$rows" >>"$WORK/all.tsv"
	page=$((page + 1))
done

total=$(wc -l <"$WORK/all.tsv" | tr -d ' ')
echo "共找到 $total 个 Release"

python3 - "$WORK/all.tsv" "$WORK/keep.tsv" "$WORK/del.tsv" "$KEEP_DAYS" "$KEEP_LATEST" <<'PY'
import datetime
import sys

src, keep_path, del_path, keep_days, keep_latest = sys.argv[1:6]
keep_days, keep_latest = int(keep_days), int(keep_latest)
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=keep_days)

rows = []
with open(src, encoding='utf-8') as f:
    for line in f:
        if not line.strip():
            continue
        rid, epoch, prefix, tag = line.rstrip('\n').split('\t')
        rows.append((int(epoch), rid, prefix, tag))
rows.sort(reverse=True)

seen = {}
kept = deleted = expired = 0
with open(keep_path, 'w', encoding='utf-8') as keep, open(del_path, 'w', encoding='utf-8') as gone:
    for epoch, rid, prefix, tag in rows:
        index = seen.get(prefix, 0)
        seen[prefix] = index + 1
        fresh = epoch >= cutoff.timestamp()
        if index < keep_latest or fresh:
            keep.write(f'{rid}\t{tag}\n')
            kept += 1
        else:
            gone.write(f'{rid}\t{tag}\n')
            deleted += 1
            if not fresh:
                expired += 1

print(f'保留 {kept} 个（其中每种配置最新 {keep_latest} 个强制保留），删除 {deleted} 个（超期 {expired} 个）')
PY

deleted=0
failed=0
if [ -s "$WORK/del.tsv" ]; then
	while IFS=$'\t' read -r id tag; do
		[ -n "${id:-}" ] || continue
		if [ "$DRY_RUN" = "true" ]; then
			echo "would delete: $tag"
			continue
		fi
		if ! api -X DELETE "$API/releases/$id" >/dev/null; then
			echo "删除 Release 失败: $tag" >&2
			failed=$((failed + 1))
			continue
		fi
		# tag 可能已被其他途径删除，失败不算错
		api -X DELETE "$API/git/refs/tags/$tag" >/dev/null 2>&1 || true
		echo "deleted: $tag"
		deleted=$((deleted + 1))
	done <"$WORK/del.tsv"
fi

echo "--- 汇总 ---"
echo "实际删除: $deleted 个 Release"
if [ "$failed" -gt 0 ]; then
	echo "删除失败: $failed 个" >&2
	exit 1
fi
exit 0
