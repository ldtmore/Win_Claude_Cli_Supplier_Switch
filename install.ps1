# ============================================================================
#  install.ps1 - Claude Code 多供应商切换工具（ccs）一键部署
#  适用: Windows 10/11 · PowerShell 5.1 / PowerShell 7
#  用法: powershell -ExecutionPolicy Bypass -File .\install.ps1
#  幂等: 重复运行安全——已存在的配置不会被覆盖，Profile 已挂载则跳过
#  说明: 远程安装时由 install-remote.ps1 通过 -SrcDir 传入下载缓存目录
# ============================================================================
param(
    [string]$SrcDir,
    [switch]$SkipBash
)

$ErrorActionPreference = 'Stop'
$src = if ($SrcDir) { $SrcDir } else { $PSScriptRoot }
$claudeDir = Join-Path $HOME '.claude'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Step { param([string]$Msg) Write-Host ('  -> ' + $Msg) }
function Write-Ok   { param([string]$Msg) Write-Host ('  [OK] ' + $Msg) -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host ('  [跳过] ' + $Msg) -ForegroundColor DarkGray }
function Write-Warn2 { param([string]$Msg) Write-Host ('  [警告] ' + $Msg) -ForegroundColor Yellow }

Write-Host ''
Write-Host '===== Claude Code 多供应商切换工具（ccs）部署 =====' -ForegroundColor Cyan
Write-Host ''

# ---------- 环境检查（仅提示，不阻断） ----------
Write-Host '[1/4] 环境检查' -ForegroundColor Cyan
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Ok ('claude 已安装: ' + (@(& claude --version 2>$null) -join ' '))
} else {
    Write-Warn2 '未检测到 claude 命令，请先安装: npm install -g @anthropic-ai/claude-code'
}
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Ok ('node 已安装: ' + (& node --version 2>$null))
} else {
    Write-Warn2 '未检测到 node（Git Bash 端解析 JSON 需要；claude-code 依赖 node，通常都已安装）'
}
Write-Host ''

# ---------- 复制菜单脚本 ----------
Write-Host '[2/4] 复制菜单脚本到 ~/.claude' -ForegroundColor Cyan
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }
foreach ($f in @('claude-menu.ps1', 'claude-menu.sh', 'suppliers.help.md')) {
    $p = Join-Path $src $f
    if (-not (Test-Path $p)) { Write-Warn2 ('包内缺少文件: ' + $f + '（请保持文件夹完整）'); continue }
    Copy-Item -Path $p -Destination (Join-Path $claudeDir $f) -Force
    Write-Step ('已复制 ' + $f)
}
$supJson = Join-Path $claudeDir 'suppliers.json'
$tpl = Join-Path $src 'suppliers.template.json'
if (Test-Path $supJson) {
    Write-Skip 'suppliers.json 已存在，保留你的现有配置'
} elseif (Test-Path $tpl) {
    Copy-Item -Path $tpl -Destination $supJson
    Write-Step '已从模板创建 suppliers.json（记得填入你的 API Key）'
} else {
    Write-Warn2 '包内缺少 suppliers.template.json'
}
Write-Host ''

# ---------- 挂载三个终端的 Profile ----------
Write-Host '[3/4] 挂载终端 Profile（PS7 / PS5.1 / Git Bash）' -ForegroundColor Cyan

$psBlock = @'
# ---------- Claude Code 供应商菜单 (ccs / Claude-Supplier) ----------
if (Test-Path "$HOME\.claude\claude-menu.ps1") { . "$HOME\.claude\claude-menu.ps1" }
'@

# .bashrc 必须用 LF 换行（CRLF 会导致 bash 把 \r 当命令的一部分）
$bashBlock = (@'
# ---------- Claude Code 供应商菜单 (ccs / claude-supplier) ----------
if [ -f "$HOME/.claude/claude-menu.sh" ]; then
    . "$HOME/.claude/claude-menu.sh"
fi
'@) -replace "`r", ""

# 向一个 shell 配置文件末尾追加菜单挂载块（已挂载则跳过；追加前自动备份）
# PS Profile 用带 BOM 的 UTF-8 写入（PS5.1 中文需要），.bashrc 用无 BOM UTF-8 + LF
function Add-MenuMount {
    param([string]$Path, [string]$Block, [string]$Marker, [switch]$IsBash)
    if ($IsBash) { $Block = $Block -replace "`r", "" }
    if (Test-Path $Path) {
        $raw = [System.IO.File]::ReadAllText($Path)
        if ($raw -match [regex]::Escape($Marker)) { Write-Skip ($Path + ' 已挂载'); return }
        Copy-Item -Path $Path -Destination ($Path + '.bak-' + $stamp)
        Write-Step ('已备份原文件 -> ' + [System.IO.Path]::GetFileName($Path) + '.bak-' + $stamp)
        $enc = New-Object System.Text.UTF8Encoding(-not $IsBash.IsPresent)
        $nl = if ($IsBash) { "`n" } else { "`r`n" }
        [System.IO.File]::AppendAllText($Path, $nl + $Block + $nl, $enc)
        Write-Ok ('已挂载 -> ' + $Path)
    } else {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        $enc = New-Object System.Text.UTF8Encoding(-not $IsBash.IsPresent)
        $nl = if ($IsBash) { "`n" } else { "`r`n" }
        [System.IO.File]::WriteAllText($Path, $Block + $nl, $enc)
        Write-Ok ('已创建并挂载 -> ' + $Path)
    }
}

$doc = [Environment]::GetFolderPath('MyDocuments')
Add-MenuMount -Path (Join-Path $doc 'PowerShell\Microsoft.PowerShell_profile.ps1') -Block $psBlock -Marker 'claude-menu.ps1'
Add-MenuMount -Path (Join-Path $doc 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -Block $psBlock -Marker 'claude-menu.ps1'
if ($SkipBash) {
    Write-Skip '已按参数 -SkipBash 跳过 Git Bash'
} else {
    Add-MenuMount -Path (Join-Path $HOME '.bashrc') -Block $bashBlock -Marker 'claude-menu.sh' -IsBash
}
Write-Host ''

# ---------- 完成 ----------
Write-Host '[4/4] 部署完成，接下来的两步：' -ForegroundColor Cyan
Write-Host '  1. 编辑 ' -NoNewline; Write-Host ($supJson) -ForegroundColor Yellow
Write-Host '     把模板里的占位符替换为各账号真实 API Key（供应商增删改也在此文件）'
Write-Host '  2. 新开一个终端标签页，输入 ' -NoNewline; Write-Host 'ccs' -ForegroundColor Yellow -NoNewline; Write-Host '（或 ccs list / ccs status 验证）'
Write-Host ''
Write-Host '  官方入口（ccs 0）首次使用前，请先直接运行一次 claude 完成官方账号登录。' -ForegroundColor DarkGray
Write-Host '  卸载: .\uninstall.ps1（详细说明见 部署指南.md）' -ForegroundColor DarkGray
Write-Host ''
