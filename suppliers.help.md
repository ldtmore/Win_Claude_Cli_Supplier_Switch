# suppliers.json 格式说明

这是 Claude Code 多供应商切换菜单的数据文件（菜单命令：`Claude-Supplier` / `ccs`）。
修改本文件后**无需重启终端**，下一次运行菜单命令时自动生效；
改完可用 `ccs list`（或 `ccs -l`）快速校验格式与查看序号。

## 字段约定

- 顶层每个键 = 一个供应商标识（命令行输入时用的名字，建议全小写字母数字；
  `list` / `status` 是 `ccs` 保留子命令，不要用作供应商标识）
- `official` 是特殊条目：不带任何 `env:` 键，选中时会清理环境变量、直接启动官方 claude
- `desc`：菜单里显示的说明文字（建议不要含制表符/换行，会被替换成空格）
- `env:XXX`：启动 claude 前要设置的环境变量 XXX，可写多个；**新增 `env:` 变量无需改脚本**，
  official 启动前的清理范围会自动纳入 JSON 里出现过的所有 `env:` 键
- 文件只要是**合法 JSON** 即可：可随意折行，值里也可以出现英文双引号
  （三端统一标准 JSON 解析，Git Bash 端依赖 node，claude-code 自带）
- 供应商名匹配**大小写不敏感**（`ccs Glma` 与 `ccs glma` 等效）
- 菜单序号：`0` 固定是 official，其余供应商按文件顺序从 `1` 开始编号
  （≥10 个时序号自动补齐位数）

## 新增一个供应商

照抄现有某个供应商的对象，替换键名 / desc / token 即可（标准 JSON，可折行）：

```json
"新名字": { "desc": "说明文字", "env:ANTHROPIC_BASE_URL": "https://...", "env:ANTHROPIC_AUTH_TOKEN": "sk-xxx" }
```

## 换其他厂商（任何提供 Anthropic 协议端点的服务都能接）

只需换 `ANTHROPIC_BASE_URL` 和 token；GLM 专属的模型映射变量按需保留或删除
（各家的 Anthropic 兼容端点地址与模型名以其官方文档为准）：

```json
"deepseek": { "desc": "DeepSeek", "env:ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic", "env:ANTHROPIC_AUTH_TOKEN": "sk-xxx", "env:ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-chat", "env:ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-chat", "env:ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-chat" },
"kimi": { "desc": "Kimi", "env:ANTHROPIC_BASE_URL": "https://api.moonshot.cn/anthropic", "env:ANTHROPIC_AUTH_TOKEN": "sk-xxx", "env:ANTHROPIC_DEFAULT_OPUS_MODEL": "kimi-k2", "env:ANTHROPIC_DEFAULT_SONNET_MODEL": "kimi-k2", "env:ANTHROPIC_DEFAULT_HAIKU_MODEL": "kimi-k2" }
```

> 注意：Claude Code 走 **Anthropic 协议**。智谱要用 `/api/anthropic` 端点，
> 不要填 `/api/coding/paas/v4`（那是 OpenAI 协议端点，给 Cline 等工具用的）。

## GLM 模型映射说明

- 模型映射（智谱官方推荐）：Opus / Sonnet → `glm-5.3[1m]`，Haiku → `glm-5.3-flash[1m]`
- `[1m]` 后缀 = 百万 token 上下文版；如果启动时报"模型不存在"（套餐不含百万上下文），
  把 JSON 里的 `[1m]` 删掉即可，同时可删掉 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
- Haiku 档承载了大量后台小任务（会话摘要、起标题等），映射到 flash 可大幅省积分
- 会话内 `/model` 选 Sonnet/Opus 实际都是 glm-5.3，选 Haiku（轻量档）是 glm-5.3-flash

## 记录文件

- `~/.claude/.supplier-last`：记录上次使用的供应商（格式为"供应商名<TAB>时间"），
  菜单里"直接回车 = 上次使用"依赖它。每次选中供应商并确认 `claude` 命令可用后写入；
  删除该文件即可清除记录

## 安全提醒

- suppliers.json 内是**明文 API Key**：不要提交到 git 仓库、不要截图或粘贴到公开场合、
  不要放进网盘同步目录
- `ccs status` 显示的 Key 指纹（头 6 位 + 尾 4 位）可用于核对，不会泄露完整密钥
