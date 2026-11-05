#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# 自动同步上游 VIKINGYFY/OpenWRT-CI，并保留本地定制。
#
# 策略：
#   - .github/upstream-sync-owned.txt 中列出的文件：冲突时保留【本地】版本
#   - 其它文件冲突：取【上游】版本，并自动开 PR 提醒复核
#   - 合并后跑 .github/scripts/validate-sync.sh 静态校验，不通过则开 PR
#   - 无冲突且校验通过：直接快进推送 main
#
# 环境变量：
#   UPSTREAM_REPO  上游仓库，默认 VIKINGYFY/OpenWRT-CI
#   UPSTREAM_REF   上游分支，默认 main
#   BASE_BRANCH    同步目标分支，默认 main
#   SYNC_BRANCH    需要 PR 时使用的工作分支，默认 auto/upstream-sync
#   OWNED_FILE     冲突白名单，默认 .github/upstream-sync-owned.txt
#   FORCE_PR       为 true 时即使无需复核也走 PR
#   DRY_RUN        为 true 时不推送、不建 PR（本地调试用）

set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1

UPSTREAM_REPO="${UPSTREAM_REPO:-VIKINGYFY/OpenWRT-CI}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/${UPSTREAM_REPO}.git}"
UPSTREAM_REF="${UPSTREAM_REF:-main}"
BASE_BRANCH="${BASE_BRANCH:-main}"
SYNC_BRANCH="${SYNC_BRANCH:-auto/upstream-sync}"
OWNED_FILE="${OWNED_FILE:-.github/upstream-sync-owned.txt}"
FORCE_PR="${FORCE_PR:-false}"
DRY_RUN="${DRY_RUN:-false}"
VALIDATE_SCRIPT="${VALIDATE_SCRIPT:-.github/scripts/validate-sync.sh}"
SKIP_VALIDATE="${SKIP_VALIDATE:-false}"
REMOTE="${REMOTE:-origin}"
UPSTREAM_REMOTE_REF="refs/remotes/upstream/${UPSTREAM_REF}"

log() { printf '%s\n' "$*"; }
set_output() { [ -n "${GITHUB_OUTPUT:-}" ] && printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT" || true; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY" || true; }

is_owned() {
	local file="$1" pattern
	[ -f "$OWNED_FILE" ] || return 1
	while IFS= read -r pattern; do
		case "$pattern" in '' | \#*) continue ;; esac
		# shellcheck disable=SC2053
		[[ "$file" == $pattern ]] && return 0
	done <"$OWNED_FILE"
	return 1
}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# ------------------------------------------------------------------ 拉取上游
log "::group::Fetch upstream ${UPSTREAM_REPO}@${UPSTREAM_REF}"
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git remote set-url upstream "$UPSTREAM_URL"
git fetch --no-tags --prune upstream "+refs/heads/${UPSTREAM_REF}:${UPSTREAM_REMOTE_REF}"
log "::endgroup::"

UPSTREAM_SHORT=$(git rev-parse --short=10 "$UPSTREAM_REMOTE_REF")
LOCAL_SHORT=$(git rev-parse --short=10 HEAD)
log "本地 ${BASE_BRANCH}: ${LOCAL_SHORT} / 上游 ${UPSTREAM_REF}: ${UPSTREAM_SHORT}"

if git merge-base --is-ancestor "$UPSTREAM_REMOTE_REF" HEAD; then
	log "✅ 已包含上游全部提交，无需同步"
	summary "### Upstream-Sync ✅ 已是最新（上游 \`${UPSTREAM_SHORT}\`）"
	set_output "mode" "up-to-date"
	exit 0
fi

UPSTREAM_COUNT=$(git rev-list --count "HEAD..${UPSTREAM_REMOTE_REF}")
UPSTREAM_LOG=$(git log --oneline --no-decorate "HEAD..${UPSTREAM_REMOTE_REF}" | head -60)
log "上游领先 ${UPSTREAM_COUNT} 个提交"

# -------------------------------------------------------------------- 合并
git switch -C "$SYNC_BRANCH" >/dev/null 2>&1 || git switch -c "$SYNC_BRANCH"

set +e
git merge --no-ff --no-commit "$UPSTREAM_REMOTE_REF" >/tmp/sync-merge.log 2>&1
MERGE_RC=$?
set -e
cat /tmp/sync-merge.log

CONFLICTED=()
mapfile -t CONFLICTED < <(git diff --name-only --diff-filter=U)
if [ "$MERGE_RC" -ne 0 ] && [ "${#CONFLICTED[@]}" -eq 0 ]; then
	log "::error::合并失败且没有冲突文件，请检查上游历史"
	git merge --abort || true
	exit 1
fi

KEPT=()
THEIRS=()
for file in "${CONFLICTED[@]}"; do
	has_ours=0
	has_theirs=0
	git cat-file -e ":2:${file}" 2>/dev/null && has_ours=1 || true
	git cat-file -e ":3:${file}" 2>/dev/null && has_theirs=1 || true

	if is_owned "$file" && [ "$has_ours" -eq 1 ]; then
		git checkout --ours -- "$file"
		git add -- "$file"
		KEPT+=("$file")
	elif [ "$has_theirs" -eq 1 ]; then
		git checkout --theirs -- "$file"
		git add -- "$file"
		THEIRS+=("$file")
	elif [ "$has_ours" -eq 1 ]; then
		git checkout --ours -- "$file"
		git add -- "$file"
		KEPT+=("$file")
	else
		git rm -q -- "$file" || true
		THEIRS+=("${file}（上游删除）")
	fi
done

if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
	{
		echo "Sync upstream ${UPSTREAM_REPO}@${UPSTREAM_REF} (${UPSTREAM_SHORT}) into ${BASE_BRANCH}"
		echo
		echo "上游提交数：${UPSTREAM_COUNT}"
		[ "${#KEPT[@]}" -gt 0 ] && printf '保留本地版本：%s\n' "${KEPT[*]}"
		[ "${#THEIRS[@]}" -gt 0 ] && printf '采用上游版本：%s\n' "${THEIRS[*]}"
	} >/tmp/sync-commit-msg.txt
	git add -A
	git commit -q --no-verify -F /tmp/sync-commit-msg.txt
else
	log "上游没有需要合并的改动"
	git switch "$BASE_BRANCH" >/dev/null 2>&1 || true
	exit 0
fi

# -------------------------------------------------------------------- 校验
log "::group::Static validation"
set +e
if [ "$SKIP_VALIDATE" = "true" ] || [ ! -f "$VALIDATE_SCRIPT" ]; then
	echo "(跳过静态校验)"
	echo "(跳过静态校验)" >/tmp/sync-validate.log
	VALIDATE_RC=0
else
	bash "$VALIDATE_SCRIPT" 2>&1 | tee /tmp/sync-validate.log
	VALIDATE_RC=${PIPESTATUS[0]}
fi
set -e
log "::endgroup::"

NEED_PR=false
REASONS=()
if [ "${#THEIRS[@]}" -gt 0 ]; then
	NEED_PR=true
	REASONS+=("有 ${#THEIRS[@]} 个非白名单文件冲突，已自动采用上游版本，需复核")
fi
if [ "$VALIDATE_RC" -ne 0 ]; then
	NEED_PR=true
	REASONS+=("静态校验未通过")
fi
if [ "$FORCE_PR" = "true" ]; then
	NEED_PR=true
	REASONS+=("手动要求走 PR")
fi

# ---------------------------------------------------------------- 直接推 main
if [ "$NEED_PR" = "false" ]; then
	if [ "$DRY_RUN" = "true" ]; then
		log "[dry-run] 将直接推送 ${BASE_BRANCH}"
		set_output "mode" "dry-run-push"
		exit 0
	fi

	log "::group::Push ${BASE_BRANCH}"
	if git push "$REMOTE" "HEAD:refs/heads/${BASE_BRANCH}"; then
		log "::endgroup::"
		git push "$REMOTE" --delete "$SYNC_BRANCH" >/dev/null 2>&1 || true
		git switch "$BASE_BRANCH" >/dev/null 2>&1 || true
		log "✅ 已自动合并上游并推送 ${BASE_BRANCH}"
		{
			echo "### Upstream-Sync ✅ 已自动推送 \`${BASE_BRANCH}\`"
			echo
			echo "- 上游：\`${UPSTREAM_REPO}@${UPSTREAM_REF}\` (\`${UPSTREAM_SHORT}\`)"
			echo "- 合并上游提交数：${UPSTREAM_COUNT}"
			[ "${#KEPT[@]}" -gt 0 ] && echo "- 冲突保本地：$(printf '`%s` ' "${KEPT[@]}")"
			echo "- 静态校验：通过"
			echo
			echo "<details><summary>上游提交</summary>"
			echo
			echo '```'
			echo "$UPSTREAM_LOG"
			echo '```'
			echo "</details>"
		} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
		set_output "mode" "push"
		exit 0
	fi
	log "::endgroup::"
	log "直接推送失败，改为开 PR"
	NEED_PR=true
	REASONS+=("推送 ${BASE_BRANCH} 被拒绝（可能是分支保护）")
fi

# ---------------------------------------------------------------------- PR
{
	echo "## 上游自动同步：需要你复核"
	echo
	echo "- 上游：\`${UPSTREAM_REPO}@${UPSTREAM_REF}\` → \`${UPSTREAM_SHORT}\`"
	echo "- 基线：\`${BASE_BRANCH}\` (\`${LOCAL_SHORT}\`)"
	echo "- 上游新增提交：${UPSTREAM_COUNT}"
	echo
	echo "### 为什么开 PR"
	echo
	for r in "${REASONS[@]}"; do echo "- ${r}"; done
	echo
	echo "### 冲突处理"
	echo
	if [ "${#KEPT[@]}" -gt 0 ] || [ "${#THEIRS[@]}" -gt 0 ]; then
		echo "| 文件 | 处理 |"
		echo "| --- | --- |"
		for f in "${KEPT[@]}"; do echo "| \`${f}\` | 保留本地 |"; done
		for f in "${THEIRS[@]}"; do echo "| \`${f}\` | 采用上游（请复核） |"; done
	else
		echo "无冲突（自动合并）"
	fi
	echo
	echo "### 静态校验"
	echo
	echo '```'
	cat /tmp/sync-validate.log
	echo '```'
	echo
	echo "### 上游提交（前 60 条）"
	echo
	echo '```'
	echo "$UPSTREAM_LOG"
	echo '```'
} >/tmp/sync-pr-body.md

if [ "$DRY_RUN" = "true" ]; then
	log "[dry-run] 将创建/更新 PR：${SYNC_BRANCH} -> ${BASE_BRANCH}"
	sed -n '1,40p' /tmp/sync-pr-body.md
	set_output "mode" "dry-run-pr"
	exit 0
fi

log "::group::Push ${SYNC_BRANCH} and open PR"
git push --force-with-lease "$REMOTE" "HEAD:refs/heads/${SYNC_BRANCH}"

if [ -z "${GH_TOKEN:-}" ]; then
	log "::error::缺少 GH_TOKEN，无法创建 PR；分支已推送到 ${SYNC_BRANCH}"
	log "::endgroup::"
	exit 1
fi

PR_NUMBER=$(gh pr list --head "$SYNC_BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null || true)
if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ]; then
	gh pr edit "$PR_NUMBER" \
		--title "chore(upstream-sync): 同步上游 ${UPSTREAM_SHORT}" \
		--body-file /tmp/sync-pr-body.md
	log "已更新 PR #${PR_NUMBER}"
else
	PR_URL=$(gh pr create \
		--base "$BASE_BRANCH" \
		--head "$SYNC_BRANCH" \
		--title "chore(upstream-sync): 同步上游 ${UPSTREAM_SHORT}" \
		--body-file /tmp/sync-pr-body.md)
	log "已创建 PR: ${PR_URL}"
fi
log "::endgroup::"

summary "### Upstream-Sync ⚠️ 需要复核"
summary ""
for r in "${REASONS[@]}"; do summary "- ${r}"; done
summary ""
summary "分支：\`${SYNC_BRANCH}\`"
set_output "mode" "pull-request"
