# Claude Code 多供应商切换工具（ccs）

**Win_Claude_Cli_Supplier_Switch** · 一个纯脚本、零安装、零常驻进程的 Windows 终端方案：
在多个大模型供应商（智谱 GLM / DeepSeek / Kimi / 官方 Anthropic …）之间**一条命令切换
Claude Code**，不同终端窗口可同时运行不同账号。

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![Shell](https://img.shields.io/badge/shell-PowerShell%205.1%20%7C%207%20%7C%20Git%20Bash-5391FE)
![Version](https://img.shields.io/badge/version-v1.4-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## 一句话安装

在 PowerShell 里执行（无需下载任何文件）：

```powershell
irm https://raw.githubusercontent.com/ldtmore/Win_Claude_Cli_Supplier_Switch/main/install-remote.ps1 | iex
```

> 大陆网络访问 GitHub raw 受限时会自动回退 jsDelivr 镜像，也可以直接用镜像地址：
> `irm https://cdn.jsdelivr.net/gh/ldtmore/Win_Claude_Cli_Supplier_Switch@main/install-remote.ps1 | iex`
>
> 安装后编辑 `%USERPROFILE%\.claude\suppliers.json` 填入你的 API Key，新开终端输入 `ccs`。
> 前置条件：已安装 [Node.js](https://nodejs.org) 和
> Claude Code（`npm install -g @anthropic-ai/claude-code`）。

## 它解决什么问题

同一个 Claude Code，想在多个 API 供应商 / 多个付费账号之间轮换使用（多账号额度池
并行、官方与三方混用），原生做法是反复手改环境变量——麻烦、易错、且无法并行。
ccs 把这件事变成一次按键：

```text
  ── Claude Code 供应商选择 ────────────────────

   [0]  official   官方 Anthropic  （未登录）
   [1]  glma       智谱GLM · 账号A  ● 上次
   [2]  glmb       智谱GLM · 账号B

  ──────────────────────────────────────────────
  回车 = 上次使用 · 序号或名字直达 · q 退出

  选择 [上次 1 glma] ▸
```

## 核心特性

- ✅ **三终端通用**：PowerShell 7 / PowerShell 5.1 / Git Bash，行为完全一致
- ✅ **四种选法**：菜单序号 / 名字（不分大小写）/ 唯一前缀直达（`ccs glm`）/ 直接回车 = 上次
- ✅ **多窗口并行**：标签页 A 跑账号 A、标签页 B 跑账号 B，互不干扰（进程级环境变量）
- ✅ **退出自动还原**：会话结束（含 Ctrl+C）自动清理全部临时环境变量
- ✅ **零脚本维护加供应商**：只需编辑一个 JSON 文件，环境变量清理范围自动跟随
- ✅ **防呆**：输错给纠错建议、重复 API Key 检测、官方登录状态标注、三端挂载体检
- ✅ **工具命令**：`ccs list` 秒验配置、`ccs status` 一屏排障
- ✅ **零依赖**：不需要安装任何额外软件（Git Bash 端解析复用 node，claude-code 本身依赖 node）

## 本地安装（备选）

不想用远程一句式？下载或克隆本仓库后，在仓库目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

## 文档

| 文档 | 内容 |
|---|---|
| [部署指南.md](部署指南.md) | 一键 / 远程 / 手动三种部署方式、验证、升级、卸载 |
| [使用手册.md](使用手册.md) | 命令全览、suppliers.json 配置、工作原理、故障排查、版本历史 |
| [suppliers.help.md](suppliers.help.md) | 供应商配置格式说明（含 DeepSeek / Kimi 接入示例） |

## 目录结构

| 文件 | 说明 |
|---|---|
| `install.ps1` | 本地一键部署脚本（幂等，重复运行安全） |
| `install-remote.ps1` | 远程一键部署引导（从本仓库下载后调用 install.ps1） |
| `uninstall.ps1` | 一键卸载脚本（默认保留你的 suppliers.json） |
| `claude-menu.ps1` | 菜单逻辑（PowerShell 5.1/7 共用，含 Tab 补全） |
| `claude-menu.sh` | 菜单逻辑（Git Bash 版，经 node 解析 JSON） |
| `suppliers.template.json` | 供应商配置模板（部署时自动复制为 suppliers.json） |
| `suppliers.help.md` | 配置格式说明（随部署复制到 ~/.claude） |

## 适用环境

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows 10 / 11 |
| 终端 | Windows Terminal（推荐）/ 任意能跑 PowerShell 的终端 + Git Bash（可选） |
| PowerShell | 5.1（系统自带）或 7+（可选） |
| Node.js | 需要（claude-code 自身依赖） |
| Claude Code | `npm install -g @anthropic-ai/claude-code` |

## 设计理念

市面上的图形化切换器需要安装、常驻、且改的是全局配置，多窗口并行不同账号时互相
踩踏。本方案的原理是**进程级环境变量 + 数据与逻辑分离**：

1. 每个终端标签页是独立 shell 进程，选中供应商时在当前 shell 注入一组 `ANTHROPIC_*`
   变量再拉起 claude，退出后清理——天然支持并行与还原；
2. 所有供应商信息只存在于 `suppliers.json` 一个文件里，脚本不硬编码任何供应商，
   加账号 = 改一行 JSON。

## 安全说明

- `suppliers.json` 内是**明文 API Key**：不要提交到 git、不要截图外发、不要放进网盘同步
  目录（本仓库 `.gitignore` 已做防御性排除）
- 远程安装脚本只从本仓库官方地址下载文件，不执行任何第三方代码

## License

[MIT](LICENSE) © 2026 ldtmore

---

方案版本 v1.4 · 2026-08 · 纯配置 + 脚本，无第三方依赖
