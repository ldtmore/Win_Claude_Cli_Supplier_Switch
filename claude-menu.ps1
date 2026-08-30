# ============================================================================
#  claude-menu.ps1 - Claude Code 多供应商切换菜单
#  兼容 Windows PowerShell 5.1 与 PowerShell 7+（由各自 $PROFILE 引用加载）
#  数据文件: ~\.claude\suppliers.json   格式说明: ~\.claude\suppliers.help.md
# ============================================================================

$script:ClaudeMenuVersion = 'v1.4'
$script:ClaudeMenuDataFile = Join-Path $HOME '.claude\suppliers.json'
$script:ClaudeMenuLastFile = Join-Path $HOME '.claude\.supplier-last'
# 基础清理列表：official 入口启动前要清掉的环境变量。
# 除此之外，suppliers.json 里出现过的所有 env: 键会在运行时动态并入清理范围，
# 因此给供应商新增 env: 变量无需改本脚本。
$script:ClaudeMenuBaseEnv = @(
    'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_MODEL',
    'ANTHROPIC_SMALL_FAST_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL', 'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', 'API_TIMEOUT_MS'
)

# 读取 suppliers.json，返回 OrderedDictionary[key] = @{ Desc=...; Env=@{...} }；失败返回 $null
function Get-ClaudeSupplierList {
    param([switch]$Quiet)
    if (-not (Test-Path $script:ClaudeMenuDataFile)) {
        if (-not $Quiet) { Write-Host '  ✘ 找不到供应商配置文件 ~\.claude\suppliers.json' -ForegroundColor Red }
        return $null
    }
    try {
        $raw = Get-Content $script:ClaudeMenuDataFile -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json
    } catch {
        if (-not $Quiet) { Write-Host ('  ✘ suppliers.json 解析失败: {0}' -f $_.Exception.Message) -ForegroundColor Red }
        return $null
    }
    $list = [ordered]@{}
    foreach ($p in $json.PSObject.Properties) {
        if ($null -eq $p.Value -or $p.Value -isnot [PSCustomObject]) { continue }
        $entry = @{ Desc = ''; Env = @{} }
        foreach ($f in $p.Value.PSObject.Properties) {
            if ($f.Name -eq 'desc') { $entry.Desc = [string]$f.Value }
            elseif ($f.Name -like 'env:*') { $entry.Env[$f.Name.Substring(4)] = [string]$f.Value }
        }
        $list[$p.Name] = $entry
    }
    if ($list.Count -eq 0) {
        if (-not $Quiet) { Write-Host '  ✘ suppliers.json 里没有任何供应商条目' -ForegroundColor Red }
        return $null
    }
    return ,$list
}

# 菜单显示顺序: official 固定 [0]，其余供应商按文件顺序从 [1] 开始
function Get-ClaudeSupplierOrder {
    param($List)
    $order = @()
    if ($null -ne $List['official']) { $order += 'official' }
    foreach ($k in $List.Keys) { if ($k -ne 'official') { $order += $k } }
    return ,$order
}

# 大小写不敏感地查找供应商 key，找到返回标准写法，找不到返回 $null
function Find-ClaudeSupplierKey {
    param($List, [string]$Name)
    foreach ($k in $List.Keys) { if ($k -ieq $Name) { return $k } }
    return $null
}

# 输错名字时给前缀匹配建议（输入是某 key 的前缀，或某 key 是输入的前缀），无则返回 $null
function Find-ClaudeSupplierSuggestion {
    param($List, [string]$Name)
    foreach ($k in $List.Keys) {
        if ($k -like ($Name + '*') -or $Name -like ($k + '*')) { return $k }
    }
    return $null
}

# 前缀匹配：返回所有以 $Name 开头（不分大小写）的 key 数组（无匹配为空数组）
function Find-ClaudeSupplierPrefixMatches {
    param($List, [string]$Name)
    $m = @()
    foreach ($k in $List.Keys) { if ($k -like ($Name + '*')) { $m += $k } }
    return $m
}

# 官方登录检测：已登录返回账号邮箱，未登录返回 $null（读 ~/.claude.json 的 oauthAccount）
function Get-ClaudeOfficialLogin {
    try {
        $f = Join-Path $HOME '.claude.json'
        if (-not (Test-Path $f)) { return $null }
        $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.oauthAccount -and $j.oauthAccount.emailAddress) { return [string]$j.oauthAccount.emailAddress }
        return $null
    } catch { return $null }
}

# 检测某个 shell 配置文件里是否还挂着菜单引用（status 三端健康检查用）
function Test-ClaudeProfileMount {
    param([string]$Path, [string]$Marker)
    if ((Test-Path $Path) -and ((Get-Content $Path -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($Marker))) { return $true }
    return $false
}

# 按 key 最大长度自适应列宽（10～14），避免长名字推挤说明列
function Get-ClaudeKeyWidth {
    param($Order)
    $w = 10
    foreach ($k in $Order) { $l = [Math]::Min(14, $k.Length + 1); if ($l -gt $w) { $w = $l } }
    return $w
}

# 画一行供应商（list 与菜单共用）。宽度约定：整行视觉宽度 48 格，标题按中文 2 格宽手工配平
function Write-ClaudeSupplierRow {
    param($Index, $IndexWidth, $Key, $Desc, [switch]$IsLast, [int]$KeyWidth = 10, [string]$Note = '')
    $fmt = '   [{0,' + $IndexWidth + '}]  '
    Write-Host ($fmt -f $Index) -ForegroundColor Yellow -NoNewline
    Write-Host ($Key.PadRight($KeyWidth) + ' ') -NoNewline
    Write-Host $Desc -ForegroundColor DarkGray -NoNewline
    if ($Note) { Write-Host ('  ' + $Note) -ForegroundColor DarkGray -NoNewline }
    if ($IsLast) { Write-Host '  ● 上次' -ForegroundColor Green -NoNewline }
    Write-Host ''
}

function Show-ClaudeSupplierMenu {
    param($List, $LastKey)
    $order = Get-ClaudeSupplierOrder -List $List
    $idxW = ([string]($order.Count - 1)).Length
    $keyW = Get-ClaudeKeyWidth -Order $order
    $officialNote = ''
    if (($order -contains 'official') -and (-not (Get-ClaudeOfficialLogin))) { $officialNote = '（未登录）' }
    Write-Host ''
    Write-Host ('  ── Claude Code 供应商选择 ' + ('─' * 20)) -ForegroundColor Cyan
    Write-Host ''
    $i = 0
    foreach ($k in $order) {
        Write-ClaudeSupplierRow -Index $i -IndexWidth $idxW -Key $k -Desc $List[$k].Desc -IsLast:($k -eq $LastKey) -KeyWidth $keyW -Note:($(if ($k -eq 'official') { $officialNote }))
        $i++
    }
    Write-Host ''
    Write-Host ('  ' + ('─' * 46)) -ForegroundColor DarkGray
    if ($LastKey) {
        Write-Host '  回车 = 上次使用 · 序号或名字直达 · q 退出' -ForegroundColor DarkGray
    } else {
        Write-Host '  输入序号或名字直达 · q 退出' -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ccs list：无交互列表 + 配置校验（JSON 坏掉时 Get-ClaudeSupplierList 已先行报错退出）
function Show-ClaudeSupplierList {
    param($List, $LastKey)
    $order = Get-ClaudeSupplierOrder -List $List
    $idxW = ([string]($order.Count - 1)).Length
    $keyW = Get-ClaudeKeyWidth -Order $order
    $officialNote = ''
    if (($order -contains 'official') -and (-not (Get-ClaudeOfficialLogin))) { $officialNote = '（未登录）' }
    Write-Host ''
    Write-Host ('  ── Claude Code 供应商列表 ' + ('─' * 20)) -ForegroundColor Cyan
    Write-Host ''
    $i = 0
    foreach ($k in $order) {
        Write-ClaudeSupplierRow -Index $i -IndexWidth $idxW -Key $k -Desc $List[$k].Desc -IsLast:($k -eq $LastKey) -KeyWidth $keyW -Note:($(if ($k -eq 'official') { $officialNote }))
        $i++
    }
    Write-Host ''
    Write-Host ('  ✔ suppliers.json 正常 · {0} 项 · {1}' -f $order.Count, $script:ClaudeMenuDataFile) -ForegroundColor DarkGray
    Write-Host ''
}

# ccs status：排障信息一览
function Show-ClaudeSupplierStatus {
    param($List)
    $order = Get-ClaudeSupplierOrder -List $List
    Write-Host ''
    Write-Host ('  ── ccs 状态 ' + ('─' * 33)) -ForegroundColor Cyan
    Write-Host ''

    # 上次使用（.supplier-last 新格式为 "名字<TAB>时间"，兼容旧的纯名字格式）
    $last = $null; $lastTime = ''
    if (Test-Path $script:ClaudeMenuLastFile) {
        $raw = Get-Content $script:ClaudeMenuLastFile -Raw -ErrorAction SilentlyContinue
        if ($raw) {
            $parts = $raw.Trim() -split "`t", 2
            $last = Find-ClaudeSupplierKey -List $List -Name $parts[0]
            if ($parts.Count -gt 1) { $lastTime = $parts[1].Trim() }
        }
    }
    if ($last) {
        $line = ('  上次使用  : {0}（{1}）' -f $last, $List[$last].Desc)
        if ($lastTime) { $line += (' · {0}' -f $lastTime) }
        Write-Host $line
    } else {
        Write-Host '  上次使用  : （无记录）' -ForegroundColor DarkGray
    }

    $mtime = ''
    try { $mtime = (Get-Item $script:ClaudeMenuDataFile).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } catch { }
    Write-Host ('  供应商配置: {0}（{1} 项，修改于 {2}）' -f $script:ClaudeMenuDataFile, $order.Count, $mtime)
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        $ver = (@(& claude --version 2>$null) -join ' ')
        Write-Host ('  claude    : {0}  [{1}]' -f $ver, $cmd.Source)
    } else {
        Write-Host '  claude    : 未找到（npm install -g @anthropic-ai/claude-code）' -ForegroundColor Red
    }

    $login = Get-ClaudeOfficialLogin
    if ($login) {
        Write-Host ('  官方登录  : ✔ {0}' -f $login)
    } else {
        Write-Host '  官方登录  : ✘ 未登录（首次用 ccs 0 前，先手动跑一次 claude 完成登录）' -ForegroundColor Yellow
    }

    $doc = [Environment]::GetFolderPath('MyDocuments')
    $ps7 = '✘'; $ps5 = '✘'; $bsh = '✘'
    if (Test-ClaudeProfileMount -Path (Join-Path $doc 'PowerShell\Microsoft.PowerShell_profile.ps1') -Marker 'claude-menu.ps1') { $ps7 = '✔' }
    if (Test-ClaudeProfileMount -Path (Join-Path $doc 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -Marker 'claude-menu.ps1') { $ps5 = '✔' }
    if (Test-ClaudeProfileMount -Path (Join-Path $HOME '.bashrc') -Marker 'claude-menu.sh') { $bsh = '✔' }
    Write-Host ('  菜单      : {0} · PS7 {1} / PS5.1 {2} / Git Bash {3}' -f $script:ClaudeMenuVersion, $ps7, $ps5, $bsh)

    # 供应商明细：key 指纹（头6…尾4）+ 端点主机 + 重复 Key 检测
    Write-Host ''
    Write-Host '  供应商明细' -ForegroundColor Cyan
    $keyW = Get-ClaudeKeyWidth -Order $order
    $seen = @{}
    $dups = @()
    foreach ($k in $order) {
        if ($k -eq 'official') {
            Write-Host ('    {0} OAuth 官方入口' -f $k.PadRight($keyW))
            continue
        }
        $tok = $List[$k].Env['ANTHROPIC_AUTH_TOKEN']
        $url = $List[$k].Env['ANTHROPIC_BASE_URL']
        $fp = '（无 Key）'
        if ($tok) {
            if ($tok.Length -ge 10) { $fp = $tok.Substring(0, 6) + '…' + $tok.Substring($tok.Length - 4) } else { $fp = '（Key 过短）' }
            if ($seen.ContainsKey($tok)) { $dups += ('{0} 与 {1}' -f $k, $seen[$tok]) } else { $seen[$tok] = $k }
        }
        $host2 = ''
        if ($url) { try { $host2 = ([uri]$url).Host } catch { $host2 = $url } }
        Write-Host ('    {0} {1}  → {2}' -f $k.PadRight($keyW), $fp, $host2)
    }
    if ($dups.Count -gt 0) {
        Write-Host ('  ⚠ Key 重复: {0}（如非有意，请检查 suppliers.json）' -f ($dups -join '；')) -ForegroundColor Yellow
    } else {
        Write-Host '  ✔ 无重复 Key' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Clear-ClaudeMenuEnv {
    # 基础列表 ∪ JSON 中所有 env: 键的并集（-List 传入 Get-ClaudeSupplierList 的结果）
    param($List)
    $vars = @($script:ClaudeMenuBaseEnv)
    if ($List) {
        foreach ($e in $List.Values) {
            foreach ($k in $e.Env.Keys) { if ($vars -notcontains $k) { $vars += $k } }
        }
    }
    foreach ($v in $vars) { Remove-Item ('Env:' + $v) -ErrorAction SilentlyContinue }
}

function Claude-Supplier {
    # 用法: Claude-Supplier [list|status|序号|名字] [其他参数原样透传给 claude]
    $list = Get-ClaudeSupplierList
    if ($null -eq $list) { return }
    $order = Get-ClaudeSupplierOrder -List $list

    $last = $null
    if (Test-Path $script:ClaudeMenuLastFile) {
        $raw = Get-Content $script:ClaudeMenuLastFile -Raw -ErrorAction SilentlyContinue
        if ($raw) { $last = Find-ClaudeSupplierKey -List $list -Name ($raw.Trim() -split "`t")[0] }
    }

    # 保留子命令（优先于供应商名匹配，list/status 不要用作供应商标识）
    if ($args.Count -gt 0) {
        $sc = ([string]$args[0]).ToLower()
        if ($sc -in @('list', '-l', '--list')) { Show-ClaudeSupplierList -List $list -LastKey $last; return }
        if ($sc -in @('status', '-s', '--status')) { Show-ClaudeSupplierStatus -List $list; return }
    }

    $rest = @()
    $sel = $null
    if ($args.Count -gt 0) {
        $first = [string]$args[0]
        if ($first -match '^\d{1,3}$') {
            if ([int]$first -ge $order.Count) {
                Write-Host ('  ✘ 序号超出范围: {0}（有效范围 0-{1}）' -f $first, ($order.Count - 1)) -ForegroundColor Red
                return
            }
            $sel = $order[[int]$first]
            if ($args.Count -gt 1) { $rest = @($args)[1..($args.Count - 1)] }
        } else {
            $found = Find-ClaudeSupplierKey -List $list -Name $first
            if (-not $found) {
                # 唯一前缀直达：恰好只有一个 key 以输入开头时直接选中
                $pm = @(Find-ClaudeSupplierPrefixMatches -List $list -Name $first)
                if ($pm.Count -eq 1) { $found = $pm[0] }
                elseif ($pm.Count -gt 1) {
                    Write-Host ('  ✘ {0} 个前缀匹配: {1}（请输入更多字符）' -f $pm.Count, ($pm -join ' ')) -ForegroundColor Red
                    return
                }
            }
            if ($found) {
                $sel = $found
                if ($args.Count -gt 1) { $rest = @($args)[1..($args.Count - 1)] }
            } elseif ($first -like '-*') {
                $rest = @($args)   # 以 - 开头视为 claude 参数，仍弹菜单
            } else {
                $msg = ('  ✘ 未知供应商: {0}' -f $first)
                $sug = Find-ClaudeSupplierSuggestion -List $list -Name $first
                if ($sug) { $msg += ('（是不是想输 {0}?）' -f $sug) }
                Write-Host $msg -ForegroundColor Red
                return
            }
        }
    }

    if ($null -eq $sel) {
        # 菜单只画一次；输错仅提示一行后重新等待输入，不整页重画
        Show-ClaudeSupplierMenu -List $list -LastKey $last
        while ($true) {
            Write-Host '  选择 ' -ForegroundColor Yellow -NoNewline
            if ($last) {
                Write-Host ('[上次 {0} {1}] ' -f [array]::IndexOf($order, $last), $last) -ForegroundColor DarkGray -NoNewline
            }
            Write-Host '▸ ' -ForegroundColor Yellow -NoNewline
            $choice = Read-Host
            if ([string]::IsNullOrWhiteSpace($choice)) {
                if ($last) { $sel = $last; break }
                Write-Host '  ✘ 还没有使用记录，请输入序号或名字' -ForegroundColor Red
                continue
            }
            if ($choice -match '^\d{1,3}$') {
                if ([int]$choice -lt $order.Count) { $sel = $order[[int]$choice]; break }
                Write-Host ('  ✘ 序号超出范围: {0}（有效范围 0-{1}）' -f $choice, ($order.Count - 1)) -ForegroundColor Red
                continue
            }
            $found = Find-ClaudeSupplierKey -List $list -Name $choice
            if (-not $found) {
                # 唯一前缀直达；多候选则列出，无候选再走 q / 建议
                $pm = @(Find-ClaudeSupplierPrefixMatches -List $list -Name $choice)
                if ($pm.Count -eq 1) { $sel = $pm[0]; break }
                if ($pm.Count -gt 1) {
                    Write-Host ('  ✘ {0} 个前缀匹配: {1}（请输入更多字符）' -f $pm.Count, ($pm -join ' ')) -ForegroundColor Red
                    continue
                }
            }
            if ($found) { $sel = $found; break }
            # 供应商名优先于退出快捷键：即使存在名为 q 的供应商也能选中
            if ($choice -match '^[qQ]$') { Write-Host '  已取消。' -ForegroundColor DarkGray; return }
            $msg = ('  ✘ 未知供应商: {0}' -f $choice)
            $sug = Find-ClaudeSupplierSuggestion -List $list -Name $choice
            if ($sug) { $msg += ('（是不是想输 {0}?）' -f $sug) }
            Write-Host $msg -ForegroundColor Red
        }
    }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host '  ✘ 找不到 claude 命令，请先安装: npm install -g @anthropic-ai/claude-code' -ForegroundColor Red
        return
    }

    try { Set-Content -Path $script:ClaudeMenuLastFile -Value ($sel + "`t" + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -Encoding ASCII -ErrorAction Stop } catch { }

    if ($sel -eq 'official') {
        Clear-ClaudeMenuEnv -List $list
        if (-not (Get-ClaudeOfficialLogin)) {
            Write-Host '  ⚠ 未检测到官方登录，首次将进入登录流程（浏览器 OAuth，只需完成一次）' -ForegroundColor Yellow
        }
        Write-Host '  ▶ 正在启动官方 Claude Code ...' -ForegroundColor Cyan
        & claude @rest
        Write-Host ''
        Write-Host '  ✔ 会话结束。' -ForegroundColor DarkGray
        return
    }

    $entry = $list[$sel]
    Clear-ClaudeMenuEnv -List $list
    foreach ($k in $entry.Env.Keys) { Set-Item -Path ('Env:' + $k) -Value $entry.Env[$k] }
    Write-Host ('  ▶ 正在以 {0}（{1}）启动 Claude Code ...' -f $sel, $entry.Desc) -ForegroundColor Cyan
    # try/finally 保证 claude 被 Ctrl+C 打断时也能清理临时环境变量
    try {
        & claude @rest
    } finally {
        foreach ($k in $entry.Env.Keys) { Remove-Item ('Env:' + $k) -ErrorAction SilentlyContinue }
    }
    Write-Host ''
    Write-Host '  ✔ 会话结束，已清理临时环境变量。' -ForegroundColor DarkGray
}

Set-Alias -Name ccs -Value Claude-Supplier

# Tab 补全: ccs <TAB> 列出所有供应商名字（仅第一个参数位置）
Register-ArgumentCompleter -CommandName 'Claude-Supplier', 'ccs' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        $elemCount = $commandAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandElement] }, $true).Count
        if ($elemCount -gt 2) { return }
        $list = Get-ClaudeSupplierList -Quiet
        if ($null -eq $list) { return }
        $cands = @(Get-ClaudeSupplierOrder -List $list) + @('list', 'status')
        $cands |
            Where-Object { $_ -like ($wordToComplete + '*') } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    } catch { }
}
