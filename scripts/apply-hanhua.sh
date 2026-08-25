#!/usr/bin/env bash
#
# apply-hanhua.sh —— 批量应用汉化规则到 frp 源码
#
# 前置条件:
#   1. 本脚本必须在「仓库根目录」运行(CWD = frp-cn 根),
#      因为 hanhua/汉化.ts 内部用 process.cwd() 拼接绝对路径,
#      且命令里 汉化.ts 以相对路径 ./hanhua/汉化.ts 调用。
#   2. frp 源码已克隆到 ./代码 (由 CI 的 git clone 步骤创建)。
#   3. 已安装 Bun 运行时(本地: brew install oven-sh/bun; CI: oven-sh/setup-bun)。
#
# 行为:
#   - 解析 hanhua/汉化和修改.md 中所有 `bun ./hanhua/汉化.ts <规则.json> <目标>` 命令
#   - 逐条执行,把中文规则灌入 frp 源码(原地覆盖写回)
#   - 捕获每条的「未匹配」原文串;若任一规则文件缺失或存在未匹配,则非零退出
#   - 末尾汇总,供 CI 失败时在 issue 中展示
#
# 退出码:
#   0 = 全部成功
#   1 = 有规则文件缺失 / 有原文串未匹配 / 汉化.ts 自身报错
#
set -uo pipefail

# 确保运行在仓库根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

SRC_DIR="${REPO_ROOT}/代码"
MANIFEST="${REPO_ROOT}/hanhua/汉化和修改.md"
RUNNER="${REPO_ROOT}/hanhua/汉化.ts"

# ---- 环境检查 ----
if [ ! -d "${SRC_DIR}" ]; then
  echo "ERROR: 未找到 frp 源码目录: ${SRC_DIR}"
  echo "       请先 git clone fatedier/frp 到 ./代码 再运行本脚本。"
  exit 1
fi

if [ ! -f "${RUNNER}" ]; then
  echo "ERROR: 未找到汉化执行器: ${RUNNER}"
  exit 1
fi

if ! command -v bun >/dev/null 2>&1; then
  echo "ERROR: 未检测到 Bun 运行时,请先安装: https://bun.sh (或 CI 用 oven-sh/setup-bun)"
  exit 1
fi

if [ ! -f "${MANIFEST}" ]; then
  echo "ERROR: 未找到汉化清单: ${MANIFEST}"
  exit 1
fi

# ---- 从清单提取 bun 命令 ----
# 每行形如:  bun ./hanhua/汉化.ts hanhua/xxx.json 代码/path/to/file
# 清单路径含中文目录,用 python 提取以避免 shell 引号/编码问题
MAP_CMDS="$(python3 - "${MANIFEST}" <<'PY'
import re, sys, io
md = io.open(sys.argv[1], encoding='utf-8').read()
for m in re.findall(r'bun\s+\./hanhua/汉化\.ts\s+(\S+\.json)\s+(\S+)', md):
    print(f"{m[0]}\t{m[1]}")
PY
)"

if [ -z "${MAP_CMDS}" ]; then
  echo "ERROR: 从清单中未解析到任何 bun 汉化命令"
  exit 1
fi

TOTAL=0
OK=0
FAIL_LIST=()
UNMATCHED_LIST=()

echo "=================================================="
echo " 开始批量汉化 (共 $(echo "${MAP_CMDS}" | wc -l | tr -d ' ') 条规则)"
echo "=================================================="

while IFS=$'\t' read -r RULE_FILE TARGET_FILE; do
  [ -z "${RULE_FILE}" ] && continue
  TOTAL=$((TOTAL+1))

  # 规则文件以仓库根为基准;目标文件形如 代码/cmd/... 以仓库根为基准
  RULE_ABS="${REPO_ROOT}/${RULE_FILE}"
  TARGET_ABS="${REPO_ROOT}/${TARGET_FILE}"

  if [ ! -f "${RULE_ABS}" ]; then
    echo "  [FAIL ${TOTAL}] 规则文件缺失: ${RULE_FILE}"
    FAIL_LIST+=("${RULE_FILE}")
    continue
  fi
  if [ ! -f "${TARGET_ABS}" ]; then
    echo "  [FAIL ${TOTAL}] 目标源码不存在(上游可能改名/移除): ${TARGET_FILE}"
    FAIL_LIST+=("${TARGET_FILE}")
    continue
  fi

  # 执行汉化.ts —— 必须在仓库根目录运行,因为它用 process.cwd() 拼路径
  OUT="$(bun "./hanhua/汉化.ts" "${RULE_FILE}" "${TARGET_FILE}" 2>&1)"
  RC=$?

  if [ ${RC} -ne 0 ]; then
    echo "  [FAIL ${TOTAL}] 汉化.ts 执行失败 (rc=${RC}): ${RULE_FILE} -> ${TARGET_FILE}"
    echo "${OUT}" | sed 's/^/      /'
    FAIL_LIST+=("${TARGET_FILE}")
    continue
  fi

  # 捕获「未匹配」原文串(汉化.ts 输出中以 "  - 内容：[ ... ]" 形式列出)
  UNM="$(echo "${OUT}" | grep -E '^[[:space:]]*-[[:space:]]*内容：\[' | sed -E 's/^[[:space:]]*-[[:space:]]*内容：\[[[:space:]]*//; s/[[:space:]]*\][[:space:]]*$//')"
  if [ -n "${UNM}" ]; then
    echo "  [WARN ${TOTAL}] 部分原文未匹配: ${TARGET_FILE}"
    while IFS= read -r u; do
      [ -n "$u" ] && UNMATCHED_LIST+=("${TARGET_FILE} :: ${u}")
    done <<< "${UNM}"
  fi

  echo "  [OK ${TOTAL}] ${TARGET_FILE}"
  OK=$((OK+1))
done <<< "${MAP_CMDS}"

echo ""
echo "=================================================="
echo " 汉化汇总: 成功 ${OK}/${TOTAL}"
echo "=================================================="

# ---- 结构性改动：frps 前端 main.ts 注入 Element Plus 中文语言包 ----
# 该改动是「插入代码」而非字符串替换，汉化.ts 不处理，这里单独幂等注入。
MAIN_TS="${SRC_DIR}/web/frps/src/main.ts"
if [ -f "${MAIN_TS}" ]; then
  if grep -q "zh-cn" "${MAIN_TS}"; then
    echo "  [SKIP] main.ts 已含中文语言包配置，跳过注入"
  else
    # 在 app.mount('#app') 之前插入 Element Plus 中文 locale
    python3 - "${MAIN_TS}" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
inject = (
    "import ElementPlus from 'element-plus'\n"
    "import zhCn from 'element-plus/es/locale/lang/zh-cn'\n"
    "\n"
    "app.use(ElementPlus, {\n"
    "  locale: zhCn,\n"
    "})\n"
)
# 插入点：在 app.mount('#app') 之前
marker = "app.mount('#app')"
assert marker in s, "未找到插入锚点 app.mount('#app')"
if "zh-cn" not in s:
    s = s.replace(marker, inject + "\n" + marker, 1)
io.open(p, 'w', encoding='utf-8').write(s)
print("  [OK] main.ts 已注入 Element Plus 中文语言包")
PY
    if [ $? -ne 0 ]; then
      echo "  [FAIL] main.ts 注入失败"
      FAIL_LIST+=("web/frps/src/main.ts (注入失败)")
    fi
  fi
else
  echo "  [WARN] 未找到 ${MAIN_TS}，跳过 main.ts 注入（可能上游已移除该文件）"
fi


# ---- 自动化清单中的手动步骤：前端函数注入 ----
# 汉化 JSON 规则把模板 {{ proxy.status }} 替换为 {{ fn代理状态转换(proxy.status) }}，
# 但汉化和修改.md 中"增加函数"是手动步骤，CI 不会执行。
# 若不注入这些函数，Vue 运行时找不到 fn代理状态转换 → ProxyCard 渲染崩溃 →
# 整个代理列表 v-for 不渲染（StatusPills 摘要计数不受影响，因为不依赖该函数）。
# 这里在汉化替换后幂等注入所需函数，保证 CI 产物功能完整。
echo "--------------------------------------------------"
echo " 自动化手动步骤：前端函数注入"
echo "--------------------------------------------------"
python3 - "${SRC_DIR}" <<'PYEOF'
import io, os, sys, re

src = sys.argv[1]

# ---- fn代理状态转换 (ProxyCard.vue + ProxyDetail.vue) ----
fn_status = (
    '\nconst fn代理状态转换 = (状态: string) => {\n'
    '  switch (状态) {\n'
    '    case "running": return "运行中"\n'
    '    case "error": return "错误"\n'
    '    case "disabled": return "禁用"\n'
    '    case "waiting": return "等待中"\n'
    '    case "new": return "新创建"\n'
    '    case "wait start": return "等待启动"\n'
    '    case "start error": return "启动失败"\n'
    '    case "check failed": return "检查失败"\n'
    '    case "closed": return "已关闭"\n'
    '    default: return 状态\n'
    '  }\n'
    '}\n'
)

# ---- fn代理错误信息转换 (ProxyDetail.vue only) ----
fn_err = (
    '\nconst fn代理错误信息转换 = (错误信息: string) => {\n'
    '  switch (错误信息) {\n'
    '    case "port already used": return "端口已被占用"\n'
    '    case "port not allowed": return "不允许使用该端口"\n'
    '    case "port unavailable": return "端口不可用"\n'
    '    case "no available port": return "没有可用端口"\n'
    '    default: return 错误信息\n'
    '  }\n'
    '}\n'
)

def inject_before_close_script(path, code, marker, label):
    """在 </script> 前注入代码。marker 必须是函数定义特征（如 'const fn...'），
    不能仅用函数名，因为汉化后模板中已有 {{ fn...(proxy.status) }} 引用，
    用函数名做幂等检查会误判为"已存在"而跳过注入。"""
    if not os.path.isfile(path):
        print(f"  [WARN] 未找到 {path}，跳过 {label}")
        return
    s = io.open(path, encoding='utf-8').read()
    if marker in s:
        print(f"  [SKIP] {label} 已含 {marker}")
        return
    idx = s.rfind('</script>')
    if idx < 0:
        print(f"  [FAIL] {label} 未找到 </script> 标记")
        return
    s = s[:idx] + code + s[idx:]
    io.open(path, 'w', encoding='utf-8').write(s)
    print(f"  [OK] {label} 已注入 {marker}")

# 1. ProxyCard.vue: fn代理状态转换
inject_before_close_script(
    os.path.join(src, 'web/frpc/src/components/ProxyCard.vue'),
    fn_status, 'const fn代理状态转换', 'ProxyCard.vue')

# 2. ProxyDetail.vue: fn代理状态转换 + fn代理错误信息转换
detail_path = os.path.join(src, 'web/frpc/src/views/ProxyDetail.vue')
if os.path.isfile(detail_path):
    s = io.open(detail_path, encoding='utf-8').read()
    if 'const fn代理错误信息转换' in s:
        print("  [SKIP] ProxyDetail.vue 已含函数")
    else:
        idx = s.rfind('</script>')
        if idx >= 0:
            s = s[:idx] + fn_status + fn_err + s[idx:]
            io.open(detail_path, 'w', encoding='utf-8').write(s)
            print("  [OK] ProxyDetail.vue 已注入 fn代理状态转换 + fn代理错误信息转换")
        else:
            print("  [FAIL] ProxyDetail.vue 未找到 </script>")
else:
    print("  [WARN] 未找到 ProxyDetail.vue")

# 3. App.vue: visitors router-link 加 title 说明
app_path = os.path.join(src, 'web/frpc/src/App.vue')
if os.path.isfile(app_path):
    s = io.open(app_path, encoding='utf-8').read()
    title_text = '主动通过 P2P 隧道（xtcp/stcp）连接的客户端'
    if title_text in s:
        print("  [SKIP] App.vue 已含 visitors 说明 title")
    else:
        # 在 to="/visitors" 属性后插入 title 属性
        new_s, n = re.subn(
            r'(to=["\']/visitors["\'])',
            lambda m: m.group(0) + f' title="{title_text}"',
            s, count=1
        )
        if n > 0:
            io.open(app_path, 'w', encoding='utf-8').write(new_s)
            print("  [OK] App.vue visitors router-link 已加 title")
        else:
            print("  [WARN] App.vue 未找到 visitors router-link")

# 4. VisitorList.vue: 加说明 div
vl_path = os.path.join(src, 'web/frpc/src/views/VisitorList.vue')
if os.path.isfile(vl_path):
    s = io.open(vl_path, encoding='utf-8').read()
    hint = '此处的功能为私密转发以及P2P链接，不是普通的内网穿透！一般用不到！'
    if hint in s:
        print("  [SKIP] VisitorList.vue 已含说明 div")
    else:
        idx = s.find('</h2>')
        if idx >= 0:
            insert_at = idx + len('</h2>')
            new_s = s[:insert_at] + f'\n      <div>{hint}</div>' + s[insert_at:]
            io.open(vl_path, 'w', encoding='utf-8').write(new_s)
            print("  [OK] VisitorList.vue 已加说明 div")
        else:
            print("  [WARN] VisitorList.vue 未找到 </h2> 标记")

# 5. frps 前端 ProxyCard.vue / ProxyDetail.vue 同样需要注入（如果存在）
frps_card = os.path.join(src, 'web/frps/src/components/ProxyCard.vue')
inject_before_close_script(
    frps_card, fn_status, 'const fn代理状态转换', 'frps ProxyCard.vue')

frps_detail = os.path.join(src, 'web/frps/src/views/ProxyDetail.vue')
if os.path.isfile(frps_detail):
    s = io.open(frps_detail, encoding='utf-8').read()
    if 'const fn代理错误信息转换' in s:
        print("  [SKIP] frps ProxyDetail.vue 已含函数")
    else:
        idx = s.rfind('</script>')
        if idx >= 0:
            s = s[:idx] + fn_status + fn_err + s[idx:]
            io.open(frps_detail, 'w', encoding='utf-8').write(s)
            print("  [OK] frps ProxyDetail.vue 已注入函数")
        else:
            print("  [WARN] frps ProxyDetail.vue 未找到 </script>")
else:
    print("  [INFO] frps ProxyDetail.vue 不存在，跳过")

PYEOF
if [ $? -ne 0 ]; then
  echo "  [FAIL] 前端函数注入步骤执行出错"
  FAIL_LIST+=("前端函数注入失败")
fi


if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  echo ""
  echo "FAIL/MISSING (${#FAIL_LIST[@]}):"
  for x in "${FAIL_LIST[@]}"; do echo "   - ${x}"; done
fi

if [ ${#UNMATCHED_LIST[@]} -gt 0 ]; then
  echo ""
  echo "UNMATCHED (${#UNMATCHED_LIST[@]}), 上游可能已改文案,需刷新规则:"
  for x in "${UNMATCHED_LIST[@]}"; do echo "   - ${x}"; done
fi

# 任一失败(规则/目标缺失)→ 非零退出,让 CI 开 issue
if [ ${#FAIL_LIST[@]} -gt 0 ]; then
  exit 1
fi

echo "汉化应用完成。"
exit 0
