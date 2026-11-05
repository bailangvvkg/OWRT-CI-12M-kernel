#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# 合并上游后的静态校验：确保仓库仍处于"可编译"状态。
# 用法: bash .github/scripts/validate-sync.sh
# 退出码: 0 = 全部通过; 1 = 有失败项

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

FAILED=0
FAIL_MSGS=()

# GitHub runner 上是 python3，本地 Windows 可能只有 python（且存在同名 Store 占位程序）
PY=""
for cand in python3 python py; do
	if out=$("$cand" -c 'import sys; print(sys.version_info[0])' 2>/dev/null) && [ "$out" = "3" ]; then
		PY="$cand"
		break
	fi
done

ok()  { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✘\033[0m %s\n' "$*"; FAILED=$((FAILED + 1)); FAIL_MSGS+=("$*"); }
hdr() { printf '\n== %s ==\n' "$*"; }

# ---------------------------------------------------------------- 1. 冲突标记
hdr "1. 冲突标记"
if git grep -nE '^(<<<<<<< |>>>>>>> |=======$)' -- ':(exclude)*.md' >/tmp/validate-conflicts.txt 2>/dev/null; then
	bad "发现未解决的冲突标记"
	sed 's/^/     /' /tmp/validate-conflicts.txt | head -20
else
	ok "无冲突标记"
fi

# ------------------------------------------------------------- 2. Shell 语法
hdr "2. Shell 语法 (bash -n)"
SHELL_FILES=()
while IFS= read -r f; do [ -n "$f" ] && SHELL_FILES+=("$f"); done < <(git ls-files '*.sh')
SHELL_BAD=0
for f in "${SHELL_FILES[@]}"; do
	if ! ERR=$(bash -n "$f" 2>&1); then
		bad "语法错误: $f"
		printf '     %s\n' "$ERR" | head -5
		SHELL_BAD=1
	fi
done
[ "$SHELL_BAD" -eq 0 ] && ok "${#SHELL_FILES[@]} 个脚本语法正常"

# --------------------------------------------------------------- 3. YAML 解析
hdr "3. Workflow YAML 解析"
if [ -z "$PY" ]; then
	bad "未找到 python，跳过 YAML/引用校验"
elif YAML_ERR=$("$PY" - <<'PY'
import glob, sys
try:
    import yaml
except ImportError:
    print("PyYAML 未安装")
    sys.exit(2)
errors = []
for path in sorted(glob.glob('.github/workflows/*.yml')):
    try:
        with open(path, encoding='utf-8') as f:
            yaml.safe_load(f)
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{path}: {exc}")
if errors:
    print("\n".join(errors))
    sys.exit(1)
PY
); then
	ok "全部 workflow 可解析"
else
	bad "YAML 解析失败"
	printf '     %s\n' "$YAML_ERR" | head -10
fi

# ------------------------------------- 4/5. 配置与脚本引用 + 关键执行路径一致性
hdr "4. Workflow 引用完整性"
if REF_ERR=$("$PY" - <<'PY'
import glob, os, re, sys

problems = []


def load(path):
    import yaml
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


# --- 4.1 矩阵/选项里引用的 Config/<NAME>.txt 必须存在 ---
def workflow_texts():
    for path in sorted(glob.glob('.github/workflows/*.yml')):
        with open(path, encoding='utf-8') as f:
            yield path, f.read()


def on_block(doc):
    # PyYAML 会把裸 `on:` 解析成 True
    return doc.get('on') or doc.get(True) or {}


checked_configs = {}
for path, text in workflow_texts():
    names = set()
    for raw in re.findall(r'^\s*(?:#\s*)?CONFIG:\s*\[([^\]]*)\]', text, re.M):
        names.update(n.strip() for n in raw.split(',') if n.strip())
    try:
        doc = load(path)
    except Exception:
        doc = None
    if isinstance(doc, dict):
        inputs = (on_block(doc).get('workflow_dispatch') or {}).get('inputs') or {}
        cfg = inputs.get('CONFIG') or {}
        for opt in cfg.get('options') or []:
            if isinstance(opt, str) and opt.strip():
                names.add(opt.strip())
    for name in names:
        target = f'Config/{name}.txt'
        checked_configs.setdefault(target, path)

for target, src in sorted(checked_configs.items()):
    if not os.path.isfile(target):
        problems.append(f"{src}: 引用的配置不存在 -> {target}")

# --- 4.2 workflow 里调用的脚本必须存在 ---
script_refs = set()
for path, text in workflow_texts():
    for m in re.findall(r'\$GITHUB_WORKSPACE/([A-Za-z0-9_./-]+\.sh)', text):
        script_refs.add(m)
    for m in re.findall(r'(?<![\w/])(\.github/scripts/[A-Za-z0-9_.-]+\.sh)', text):
        script_refs.add(m)
for ref in sorted(script_refs):
    if not os.path.isfile(ref):
        problems.append(f"脚本不存在 -> {ref}")

# --- 4.3 关键路径一致性：Packages.sh/Handles.sh 要求从 OpenWrt 根目录执行 ---
def steps_of(path):
    doc = load(path)
    out = []
    for job in (doc.get('jobs') or {}).values():
        out.extend(job.get('steps') or [])
    return out


def run_block(steps, prefix):
    for step in steps:
        if str(step.get('name', '')).startswith(prefix):
            return step.get('run') or ''
    return None


core = '.github/workflows/WRT-CORE.yml'
if os.path.isfile(core):
    steps = steps_of(core)
    with open('Scripts/Packages.sh', encoding='utf-8') as f:
        packages = f.read()
    with open('Scripts/Handles.sh', encoding='utf-8') as f:
        handles = f.read()

    root_relative = bool(
        re.search(r'find\s+\./feeds/', packages)
        or re.search(r'find\s+\./feeds/', handles)
        or 'REPO_PATH="./package/' in packages
    )
    pkg_dir_relative = bool(re.search(r'find\s+\.\./feeds/', packages))

    for prefix in ('Custom Packages', 'Custom Settings'):
        block = run_block(steps, prefix)
        if block is None:
            problems.append(f"{core}: 找不到步骤 '{prefix}'")
            continue
        if root_relative and 'cd ./wrt/package' in block:
            problems.append(
                f"{core}: 步骤 '{prefix}' 在 ./wrt/package 下执行，"
                "但 Scripts/*.sh 使用以 OpenWrt 根目录为基准的 ./feeds、./package 路径"
            )
        if root_relative and 'cd ./wrt/' not in block:
            problems.append(f"{core}: 步骤 '{prefix}' 缺少 'cd ./wrt/'")
        if pkg_dir_relative and 'cd ./wrt/package' not in block:
            problems.append(
                f"{core}: Scripts/Packages.sh 使用 ../feeds 相对路径，"
                f"步骤 '{prefix}' 必须 'cd ./wrt/package'"
            )

# --- 4.4 脚本里用到的 WRT_* 变量必须由 workflow 定义 ---
defined = set()
for path, text in workflow_texts():
    defined.update(re.findall(r'\b(WRT_[A-Z0-9_]+)\b', text))
used = set()
for path in glob.glob('Scripts/*.sh'):
    with open(path, encoding='utf-8') as f:
        used.update(re.findall(r'\$\{?(WRT_[A-Z0-9_]+)', f.read()))
missing = sorted(used - defined)
if missing:
    problems.append("脚本使用了 workflow 未定义的变量: " + ", ".join(missing))

if problems:
    print("\n".join(problems))
    sys.exit(1)
PY
); then
	ok "配置引用 / 脚本引用 / 执行路径 / 环境变量 均一致"
else
	bad "引用或路径不一致"
	printf '     %s\n' "$REF_ERR" | head -20
fi

# -------------------------------------------------------------------- 汇总
hdr "汇总"
if [ "$FAILED" -eq 0 ]; then
	echo "全部通过 ✅"
	exit 0
fi
echo "失败 ${FAILED} 项 ❌"
for m in "${FAIL_MSGS[@]}"; do echo "  - $m"; done
exit 1
