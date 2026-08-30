# ============================================================================
#  claude-menu.sh - Claude Code 多供应商切换菜单（Git Bash / mintty）
#  数据文件: ~/.claude/suppliers.json   格式说明: ~/.claude/suppliers.help.md
#  解析方式: 通过 node 解析标准 JSON（claude-code 依赖 node，正常必装），
#            JSON 可随意折行，值里可以出现英文双引号
# ============================================================================

_CLAUDE_MENU_VERSION="v1.4"
_CLAUDE_MENU_DATA="$HOME/.claude/suppliers.json"
_CLAUDE_MENU_LAST="$HOME/.claude/.supplier-last"
# 基础清理列表：official 入口启动前要清掉的环境变量。
# 除此之外，suppliers.json 里出现过的所有 env: 键会在运行时动态并入清理范围，
# 因此给供应商新增 env: 变量无需改本脚本。
_CLAUDE_MENU_BASE_ENV="ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC API_TIMEOUT_MS"

# 解析数据文件 → 每行输出 "key<TAB>desc"，official 固定排最前；解析失败返回非 0
_claude_menu_entries() {
    [ -f "$_CLAUDE_MENU_DATA" ] || { echo "  ✘ 找不到供应商配置文件 ~/.claude/suppliers.json" >&2; return 1; }
    command -v node >/dev/null 2>&1 || { echo "  ✘ 需要 node 解析 suppliers.json（claude-code 依赖 node，请检查 node 安装）" >&2; return 1; }
    node -e '
      const fs = require("fs");
      let j;
      try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
      catch (e) { console.error("  ✘ suppliers.json 解析失败: " + e.message); process.exit(1); }
      const clean = s => String(s).replace(/[\t\r\n]+/g, " ");
      const out = [];
      if (Object.prototype.hasOwnProperty.call(j, "official"))
        out.push("official\t" + clean((j.official && j.official.desc) || ""));
      for (const k of Object.keys(j)) {
        if (k === "official") continue;
        const d = (j[k] && typeof j[k] === "object" && typeof j[k].desc === "string") ? clean(j[k].desc) : "";
        out.push(clean(k) + "\t" + d);
      }
      if (out.length === 0) { console.error("  ✘ suppliers.json 里没有任何供应商条目"); process.exit(1); }
      console.log(out.join("\n"));
    ' "$_CLAUDE_MENU_DATA"
}

# 在 entries 输出($1)中大小写不敏感地查找 $2，输出标准写法的 key；找不到返回非 0
_claude_menu_find_key() {
    local k d want="${2,,}"
    while IFS=$'\t' read -r k d; do
        [ -z "$k" ] && continue
        if [ "${k,,}" = "$want" ]; then printf '%s' "$k"; return 0; fi
    done <<< "$1"
    return 1
}

_claude_menu_has_key() { _claude_menu_find_key "$1" "$2" >/dev/null; }

# 取某个 key 的 desc，找不到就原样返回 key
_claude_menu_desc() {
    local k d
    while IFS=$'\t' read -r k d; do
        if [ "$k" = "$2" ]; then printf '%s' "$d"; return 0; fi
    done <<< "$1"
    printf '%s' "$2"
}

# 输错名字时给前缀匹配建议（输入是某 key 的前缀，或某 key 是输入的前缀）
_claude_menu_suggest() {
    local k d input="$2"
    while IFS=$'\t' read -r k d; do
        [ -z "$k" ] && continue
        if [[ "$k" == "$input"* || "$input" == "$k"* ]]; then printf '%s' "$k"; return 0; fi
    done <<< "$1"
    return 1
}

# 前缀匹配：输出所有以 $2 开头（不分大小写）的 key（空格分隔；无匹配输出空）
_claude_menu_prefix_matches() {
    local k d want="${2,,}" out=""
    while IFS=$'\t' read -r k d; do
        [ -z "$k" ] && continue
        if [[ "${k,,}" == "$want"* ]]; then out="$out $k"; fi
    done <<< "$1"
    printf '%s' "${out# }"
}

# 官方登录检测：已登录输出账号邮箱（exit 0），未登录 exit 1（读 ~/.claude.json 的 oauthAccount）
_claude_menu_official_login() {
    [ -f "$HOME/.claude.json" ] || return 1
    node -e '
      const fs = require("fs");
      try {
        const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        if (j.oauthAccount && j.oauthAccount.emailAddress) { console.log(j.oauthAccount.emailAddress); process.exit(0); }
      } catch (e) {}
      process.exit(1);
    ' "$HOME/.claude.json" 2>/dev/null
}

# 按 key 最大长度自适应列宽（10～14），避免长名字推挤说明列
_claude_menu_key_width() {
    local w=10 k l _d
    while IFS=$'\t' read -r k _d; do
        [ -z "$k" ] && continue
        l=$(( ${#k} + 1 )); [ "$l" -gt 14 ] && l=14
        [ "$l" -gt "$w" ] && w=$l
    done <<< "$1"
    printf '%s' "$w"
}

# 每个非 official 供应商一行：key<TAB>token<TAB>baseurl（status 明细用）
_claude_menu_env_summary() {
    node -e '
      const fs = require("fs");
      let j;
      try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
      catch (e) { process.exit(1); }
      for (const k of Object.keys(j)) {
        if (k === "official") continue;
        const e = (j[k] && typeof j[k] === "object") ? j[k] : {};
        console.log(k + "\t" + (e["env:ANTHROPIC_AUTH_TOKEN"] || "") + "\t" + (e["env:ANTHROPIC_BASE_URL"] || ""));
      }
    ' "$_CLAUDE_MENU_DATA" 2>/dev/null
}

# 取某个供应商的全部 env 对，输出 NUL 分隔的 name\0value\0 序列
_claude_menu_env_pairs() {
    node -e '
      const fs = require("fs");
      let j;
      try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
      catch (e) { process.exit(1); }
      let e = {};
      for (const k of Object.keys(j)) {
        if (k.toLowerCase() === process.argv[2].toLowerCase()) { e = j[k] || {}; break; }
      }
      const chunks = [];
      for (const f of Object.keys(e)) {
        if (f.indexOf("env:") === 0) chunks.push(f.slice(4) + "\0" + String(e[f]));
      }
      process.stdout.write(chunks.join("\0") + (chunks.length ? "\0" : ""));
    ' "$_CLAUDE_MENU_DATA" "$1"
}

# JSON 中出现过的所有 env: 变量名（每行一个），用于动态扩充清理范围
_claude_menu_env_names() {
    node -e '
      const fs = require("fs");
      let j;
      try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
      catch (e) { process.exit(1); }
      const names = new Set();
      for (const k of Object.keys(j)) {
        const e = j[k];
        if (e && typeof e === "object") {
          for (const f of Object.keys(e)) if (f.indexOf("env:") === 0) names.add(f.slice(4));
        }
      }
      console.log([...names].join("\n"));
    ' "$_CLAUDE_MENU_DATA"
}

# 清理 = 基础列表 ∪ JSON 全部 env: 键
_claude_menu_clear_env() {
    local v
    for v in $_CLAUDE_MENU_BASE_ENV; do unset "$v" 2>/dev/null; done
    while IFS= read -r v; do [ -n "$v" ] && unset "$v" 2>/dev/null; done < <(_claude_menu_env_names 2>/dev/null)
    return 0
}

# 序号列宽：按最大序号位数补齐（供应商 ≥ 10 个时保持对齐）
_claude_menu_idx_width() {
    local n
    n=$(( $(printf '%s\n' "$1" | wc -l) - 1 ))
    echo ${#n}
}

# 画一行供应商（菜单与 list 共用）。宽度约定：整行视觉 48 格，标题按中文 2 格宽手工配平
# $1=idx $2=idxwidth $3=key $4=desc $5=last标记(1/0) $6=keywidth $7=附加注释
_claude_menu_row() {
    local mark=""
    [ "$5" = "1" ] && mark=$'  \e[32m● 上次\e[0m'
    local note=""
    [ -n "$7" ] && note=$'  \e[2m'"$7"$'\e[0m'
    printf '   \e[33m[%*d]\e[0m  %-*s \e[2m%s\e[0m%s%s\n' "$2" "$1" "$6" "$3" "$4" "$note" "$mark"
}

_claude_menu_show() {
    local last="$1"
    local list key desc w w2 idx=0 note
    list=$(_claude_menu_entries) || return 1
    w=$(_claude_menu_idx_width "$list")
    w2=$(_claude_menu_key_width "$list")
    note=""
    if printf '%s\n' "$list" | grep -q $'^official\t' && ! _claude_menu_official_login; then
        note="（未登录）"
    fi
    echo
    printf '  \e[36m── Claude Code 供应商选择 ────────────────────\e[0m\n'
    echo
    while IFS=$'\t' read -r key desc; do
        [ -z "$key" ] && continue
        _claude_menu_row "$idx" "$w" "$key" "$desc" "$([ "$key" = "$last" ] && echo 1 || echo 0)" "$w2" "$([ "$key" = "official" ] && printf '%s' "$note")"
        idx=$((idx + 1))
    done <<< "$list"
    echo
    printf '  \e[2m──────────────────────────────────────────────\e[0m\n'
    if [ -n "$last" ]; then
        printf '  \e[2m回车 = 上次使用 · 序号或名字直达 · q 退出\e[0m\n'
    else
        printf '  \e[2m输入序号或名字直达 · q 退出\e[0m\n'
    fi
    echo
    return 0
}

# ccs list：无交互列表 + 配置校验（JSON 坏掉时 _claude_menu_entries 已先行报错）
_claude_menu_list() {
    local list last key desc w w2 idx=0 note
    list=$(_claude_menu_entries) || return 1
    last=""
    [ -f "$_CLAUDE_MENU_LAST" ] && last="$( < "$_CLAUDE_MENU_LAST" )"
    last="${last%%$'\t'*}"
    w=$(_claude_menu_idx_width "$list")
    w2=$(_claude_menu_key_width "$list")
    note=""
    if printf '%s\n' "$list" | grep -q $'^official\t' && ! _claude_menu_official_login; then
        note="（未登录）"
    fi
    echo
    printf '  \e[36m── Claude Code 供应商列表 ────────────────────\e[0m\n'
    echo
    while IFS=$'\t' read -r key desc; do
        [ -z "$key" ] && continue
        _claude_menu_row "$idx" "$w" "$key" "$desc" "$([ "$key" = "$last" ] && echo 1 || echo 0)" "$w2" "$([ "$key" = "official" ] && printf '%s' "$note")"
        idx=$((idx + 1))
    done <<< "$list"
    echo
    printf '  \e[2m✔ suppliers.json 正常 · %d 项 · %s\e[0m\n' "$(printf '%s\n' "$list" | wc -l)" "$_CLAUDE_MENU_DATA"
    echo
    return 0
}

# ccs status：排障信息一览
_claude_menu_status() {
    local list count full last last_time desc mtime ver cpath login line
    local k d tok url fp host2 w2 doc ps7 ps5 bsh
    list=$(_claude_menu_entries) || return 1
    count=$(printf '%s\n' "$list" | wc -l)
    # .supplier-last 新格式为 "名字<TAB>时间"，兼容旧的纯名字格式
    full=""
    [ -f "$_CLAUDE_MENU_LAST" ] && full="$( < "$_CLAUDE_MENU_LAST" )"
    last="${full%%$'\t'*}"
    last_time=""
    [[ "$full" == *$'\t'* ]] && last_time="${full#*$'\t'}"
    echo
    printf '  \e[36m── ccs 状态 ─────────────────────────────────\e[0m\n'
    echo
    if [ -n "$last" ] && _claude_menu_has_key "$list" "$last"; then
        desc=$(_claude_menu_desc "$list" "$last")
        line="  上次使用  : ${last}（${desc}）"
        [ -n "$last_time" ] && line="${line} · ${last_time}"
        printf '%s\n' "$line"
    else
        printf '  \e[2m上次使用  : （无记录）\e[0m\n'
    fi
    mtime=$(date -r "$_CLAUDE_MENU_DATA" '+%Y-%m-%d %H:%M' 2>/dev/null)
    printf '  供应商配置: %s（%d 项，修改于 %s）\n' "$_CLAUDE_MENU_DATA" "$count" "$mtime"
    if cpath=$(command -v claude); then
        ver=$(command claude --version 2>/dev/null | head -n1)
        printf '  claude    : %s  [%s]\n' "$ver" "$cpath"
    else
        printf '  \e[31mclaude    : 未找到（npm install -g @anthropic-ai/claude-code）\e[0m\n'
    fi
    login=$(_claude_menu_official_login 2>/dev/null)
    if [ -n "$login" ]; then
        printf '  官方登录  : ✔ %s\n' "$login"
    else
        printf '  \e[33m官方登录  : ✘ 未登录（首次用 ccs 0 前，先手动跑一次 claude 完成登录）\e[0m\n'
    fi
    # 三端挂载检测（Documents 可能被 OneDrive 重定向，按候选路径找）
    doc=""
    local c
    for c in "$USERPROFILE/Documents" "$USERPROFILE/OneDrive/Documents" "$USERPROFILE/OneDrive/文档"; do
        [ -d "$c" ] && doc="$c" && break
    done
    [ -n "$doc" ] || doc="$USERPROFILE/Documents"
    ps7="✘"; ps5="✘"; bsh="✘"
    grep -qs "claude-menu.ps1" "$doc/PowerShell/Microsoft.PowerShell_profile.ps1" 2>/dev/null && ps7="✔"
    grep -qs "claude-menu.ps1" "$doc/WindowsPowerShell/Microsoft.PowerShell_profile.ps1" 2>/dev/null && ps5="✔"
    grep -qs "claude-menu.sh" "$HOME/.bashrc" 2>/dev/null && bsh="✔"
    printf '  菜单      : %s · PS7 %s / PS5.1 %s / Git Bash %s\n' "$_CLAUDE_MENU_VERSION" "$ps7" "$ps5" "$bsh"

    # 供应商明细：key 指纹（头6…尾4）+ 端点主机 + 重复 Key 检测
    echo
    printf '  \e[36m供应商明细\e[0m\n'
    w2=$(_claude_menu_key_width "$list")
    local -A seen=()
    local dups=""
    while IFS=$'\t' read -r k tok url; do
        [ -z "$k" ] && continue
        if [ "$k" = "official" ]; then
            printf '    %-*s OAuth 官方入口\n' "$w2" "$k"
            continue
        fi
        fp="（无 Key）"
        if [ -n "$tok" ]; then
            if [ "${#tok}" -ge 10 ]; then fp="${tok:0:6}…${tok: -4}"; else fp="（Key 过短）"; fi
            if [ -n "${seen[$tok]+x}" ]; then
                dups="${dups:+$dups；}${k} 与 ${seen[$tok]}"
            else
                seen["$tok"]="$k"
            fi
        fi
        host2="$url"
        [[ "$url" =~ ^[a-zA-Z]+://([^/]+) ]] && host2="${BASH_REMATCH[1]}"
        printf '    %-*s %s  → %s\n' "$w2" "$k" "$fp" "$host2"
    done < <(_claude_menu_env_summary)
    if [ -n "$dups" ]; then
        printf '  \e[33m⚠ Key 重复: %s（如非有意，请检查 suppliers.json）\e[0m\n' "$dups"
    else
        printf '  \e[2m✔ 无重复 Key\e[0m\n'
    fi
    echo
    return 0
}

claude-supplier() {
    # 用法: claude-supplier [list|status|序号|名字] [其他参数原样透传给 claude]
    local list sel="" rest=() last full choice first is_key desc total pfx lidx pm pc v
    list=$(_claude_menu_entries) || return 1
    total=$(printf '%s\n' "$list" | wc -l)

    # .supplier-last 新格式为 "名字<TAB>时间"，主函数只取名字（时间在 status 里展示）
    last=""
    if [ -f "$_CLAUDE_MENU_LAST" ]; then
        full="$( < "$_CLAUDE_MENU_LAST" )"
        last="${full%%$'\t'*}"
    fi

    # 保留子命令（优先于供应商名匹配，list/status 不要用作供应商标识；不分大小写）
    local scmd="${1-}"
    case "${scmd,,}" in
        list|-l|--list)     _claude_menu_list; return $? ;;
        status|-s|--status) _claude_menu_status; return $? ;;
    esac

    if [ $# -gt 0 ]; then
        first="$1"
        if [[ "$first" =~ ^[0-9]{1,3}$ ]]; then
            if [ $((10#$first)) -ge "$total" ]; then
                printf '  \e[31m✘ 序号超出范围: %s（有效范围 0-%d）\e[0m\n' "$first" $((total - 1))
                return 1
            fi
            sel=$(printf '%s\n' "$list" | sed -n "$((10#$first + 1))p" | cut -f1)
            shift
            rest=("$@")
        else
            is_key=$(_claude_menu_find_key "$list" "$first")
            if [ -z "$is_key" ]; then
                # 唯一前缀直达：恰好只有一个 key 以输入开头时直接选中
                pm=$(_claude_menu_prefix_matches "$list" "$first")
                pc=$(printf '%s' "$pm" | wc -w)
                if [ "$pc" -eq 1 ]; then
                    is_key="$pm"
                elif [ "$pc" -gt 1 ]; then
                    printf '  \e[31m✘ %d 个前缀匹配: %s（请输入更多字符）\e[0m\n' "$pc" "$pm"
                    return 1
                fi
            fi
            if [ -n "$is_key" ]; then
                sel="$is_key"
                shift
                rest=("$@")
            elif [[ "$first" == -* ]]; then
                rest=("$@")   # 以 - 开头视为 claude 参数，仍弹菜单
            else
                printf '  \e[31m✘ 未知供应商: %s' "$first"
                is_key=$(_claude_menu_suggest "$list" "$first")
                [ -n "$is_key" ] && printf '（是不是想输 %s?）' "$is_key"
                printf '\e[0m\n'
                return 1
            fi
        fi
    fi

    if [ -z "$sel" ]; then
        # 菜单只画一次；输错仅提示一行后重新等待输入，不整页重画
        _claude_menu_show "$last" || return 1
        pfx=""
        if [ -n "$last" ] && _claude_menu_has_key "$list" "$last"; then
            lidx=$(printf '%s\n' "$list" | awk -F'\t' -v k="$last" '$1==k{print NR-1; exit}')
            pfx="[上次 ${lidx} ${last}]"
        fi
        while :; do
            printf '  \e[33m选择 \e[0m'
            [ -n "$pfx" ] && printf '\e[2m%s \e[0m' "$pfx"
            printf '\e[33m▸ \e[0m'
            # -e 启用 readline：方向键/Home/End 可编辑输入
            IFS= read -e -r choice || { echo; return 0; }
            case "$choice" in
                "")
                    if [ -n "$last" ] && _claude_menu_has_key "$list" "$last"; then
                        sel="$last"
                        break
                    fi
                    printf '  \e[31m✘ 还没有使用记录，请输入序号或名字\e[0m\n'
                    ;;
                *[!0-9]*)
                    is_key=$(_claude_menu_find_key "$list" "$choice")
                    if [ -n "$is_key" ]; then
                        sel="$is_key"
                        break
                    fi
                    # 唯一前缀直达；多候选则列出，无候选再走 q / 建议
                    pm=$(_claude_menu_prefix_matches "$list" "$choice")
                    pc=$(printf '%s' "$pm" | wc -w)
                    if [ "$pc" -eq 1 ]; then
                        sel="$pm"
                        break
                    fi
                    if [ "$pc" -gt 1 ]; then
                        printf '  \e[31m✘ %d 个前缀匹配: %s（请输入更多字符）\e[0m\n' "$pc" "$pm"
                        continue
                    fi
                    # 供应商名优先于退出快捷键：即使存在名为 q 的供应商也能选中
                    case "$choice" in
                        q | Q)
                            printf '  \e[2m已取消。\e[0m\n'
                            return 0
                            ;;
                    esac
                    printf '  \e[31m✘ 未知供应商: %s' "$choice"
                    is_key=$(_claude_menu_suggest "$list" "$choice")
                    [ -n "$is_key" ] && printf '（是不是想输 %s?）' "$is_key"
                    printf '\e[0m\n'
                    ;;
                *)
                    if [ $((10#$choice)) -lt "$total" ]; then
                        sel=$(printf '%s\n' "$list" | sed -n "$((10#$choice + 1))p" | cut -f1)
                        break
                    fi
                    printf '  \e[31m✘ 序号超出范围: %s（有效范围 0-%d）\e[0m\n' "$choice" $((total - 1))
                    ;;
            esac
        done
    fi

    command -v claude >/dev/null 2>&1 || {
        printf '  \e[31m✘ 找不到 claude 命令，请先安装: npm install -g @anthropic-ai/claude-code\e[0m\n'
        return 1
    }

    printf '%s\t%s\n' "$sel" "$(date '+%Y-%m-%d %H:%M')" > "$_CLAUDE_MENU_LAST" 2>/dev/null

    if [ "$sel" = "official" ]; then
        _claude_menu_clear_env
        _claude_menu_official_login >/dev/null 2>&1 || \
            printf '  \e[33m⚠ 未检测到官方登录，首次将进入登录流程（浏览器 OAuth，只需完成一次）\e[0m\n'
        printf '  \e[36m▶ 正在启动官方 Claude Code ...\e[0m\n'
        command claude ${rest[@]+"${rest[@]}"}
        printf '\n  \e[2m✔ 会话结束。\e[0m\n'
        return 0
    fi

    desc=$(_claude_menu_desc "$list" "$sel")
    local name value
    local -a setvars=()
    _claude_menu_clear_env
    while IFS= read -r -d '' name && IFS= read -r -d '' value; do
        export "$name=$value"
        setvars+=("$name")
    done < <(_claude_menu_env_pairs "$sel")

    printf '  \e[36m▶ 正在以 %s（%s）启动 Claude Code ...\e[0m\n' "$sel" "$desc"
    command claude ${rest[@]+"${rest[@]}"}
    for v in ${setvars[@]+"${setvars[@]}"}; do unset "$v"; done
    printf '\n  \e[2m✔ 会话结束，已清理临时环境变量。\e[0m\n'
}

ccs() { claude-supplier "$@"; }

# Tab 补全: ccs <TAB> / claude-supplier <TAB> 列出所有供应商名字（仅第一个参数位置）
_claude_menu_complete() {
    [ "${COMP_CWORD}" -ne 1 ] && return 0
    local keys
    keys="$(_claude_menu_entries 2>/dev/null | cut -f1 | tr '\n' ' ')list status "
    COMPREPLY=($(compgen -W "$keys" -- "${COMP_WORDS[COMP_CWORD]}"))
    return 0
}
complete -F _claude_menu_complete claude-supplier 2>/dev/null
complete -F _claude_menu_complete ccs 2>/dev/null
