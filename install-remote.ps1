# ============================================================================
#  install-remote.ps1 - Claude Code 多供应商切换工具（ccs）远程一键部署
#  适用: Windows 10/11 · PowerShell 5.1 / PowerShell 7
#
#  用户只需在 PowerShell 执行一句:
#      irm https://raw.githubusercontent.com/ldtmore/Win_Claude_Cli_Supplier_Switch/main/install-remote.ps1 | iex
#
#  中国大陆网络无法访问 raw.githubusercontent.com 时，自动回退 jsDelivr 镜像，
#  也可直接使用镜像地址执行:
#      irm https://cdn.jsdelivr.net/gh/ldtmore/Win_Claude_Cli_Supplier_Switch@main/install-remote.ps1 | iex
#
#  原理: 从仓库下载全部文件到临时目录 → 以脚本块方式执行 install.ps1
#  （绕过本地执行策略限制）→ 幂等部署，与本地安装完全等效
# ============================================================================
param(
    # 仓库原始文件基地址（默认即本仓库官方地址；fork 后可指向自己的仓库）
    [string]$Base = 'https://raw.githubusercontent.com/ldtmore/Win_Claude_Cli_Supplier_Switch/main',
    [switch]$SkipBash
)

$ErrorActionPreference = 'Stop'

function Write-Ok   { param([string]$Msg) Write-Host ('  [OK] ' + $Msg) -ForegroundColor Green }
function Write-Step { param([string]$Msg) Write-Host ('  -> ' + $Msg) }
function Write-Warn2 { param([string]$Msg) Write-Host ('  [警告] ' + $Msg) -ForegroundColor Yellow }

Write-Host ''
Write-Host '===== Claude Code 多供应商切换工具（ccs）远程部署 =====' -ForegroundColor Cyan
Write-Host ''

# PS 5.1 需显式启用 TLS 1.2 才能访问 HTTPS
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# 候选源：指定地址优先；GitHub raw 自动追加 jsDelivr 镜像作回退（国内网络友好）
$bases = @($Base)
if ($Base -match '^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)') {
    $bases += ('https://cdn.jsdelivr.net/gh/' + $Matches[1] + '/' + $Matches[2] + '@main')
}

$files = @('install.ps1', 'claude-menu.ps1', 'claude-menu.sh', 'suppliers.help.md', 'suppliers.template.json')
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ccs-remote-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

$okBase = $null
foreach ($b in $bases) {
    Write-Step ('尝试下载源: ' + $b)
    try {
        foreach ($f in $files) {
            Invoke-WebRequest -UseBasicParsing -Uri ($b + '/' + $f) -OutFile (Join-Path $tmp $f) -TimeoutSec 30
        }
        $okBase = $b
        break
    } catch {
        Remove-Item -Path (Join-Path $tmp '*') -Force -ErrorAction SilentlyContinue
        Write-Warn2 ('该源不可用: ' + $b)
        continue
    }
}

if (-not $okBase) {
    Write-Host ''
    Write-Host '  ✘ 所有下载源均不可用。请检查网络，或改用镜像地址执行：' -ForegroundColor Red
    Write-Host '    irm https://cdn.jsdelivr.net/gh/ldtmore/Win_Claude_Cli_Supplier_Switch@main/install-remote.ps1 | iex' -ForegroundColor Yellow
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Ok ('文件下载完成（源: ' + $okBase + '）')

# 校验下载的 install.ps1 存在
$localInstall = Join-Path $tmp 'install.ps1'
if (-not (Test-Path $localInstall)) { Write-Host '  ✘ 下载内容不完整' -ForegroundColor Red; exit 1 }

# 以脚本块方式执行安装器：不受本地执行策略限制，且无需落盘运行脚本文件
$code = Get-Content -Path $localInstall -Raw
$sb = [scriptblock]::Create($code)
if ($SkipBash) { & $sb -SrcDir $tmp -SkipBash } else { & $sb -SrcDir $tmp }

Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '  远程卸载（日后需要时执行）: irm https://raw.githubusercontent.com/ldtmore/Win_Claude_Cli_Supplier_Switch/main/uninstall.ps1 | iex' -ForegroundColor DarkGray
Write-Host ''
