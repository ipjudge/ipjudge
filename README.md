# IP 判官 · IP Judge

**[ipjudge.org](https://ipjudge.org)** —— 中立的 IP / 网络出口检测。用 ChatGPT、Claude、Gemini、Meta Muse 之前，先看清你的出口：住宅还是机房、地区是否受官方支持、有没有 DNS / WebRTC 泄露、终端和浏览器是不是走的同一条线路。

[English](#english)

这个仓库放的是**会在你机器上运行的部分**，方便你在 `curl | bash` 之前先读源码：

| 文件 | 作用 | 一行运行 |
|---|---|---|
| [`scripts/cc.sh`](scripts/cc.sh) | Claude Code / Codex 终端出口体检 | `curl -sL ipjudge.org/cc \| bash` |
| [`scripts/check.sh`](scripts/check.sh) | 服务器（VPS）一键体检 | `bash <(curl -Ls ipjudge.org/sh)` |
| [`server.json`](server.json) | MCP 服务描述（官方 MCP Registry：`org.ipjudge/ipjudge`） | 见下文 |

两个脚本都是**只读**的：不安装任何东西、不改设置、不上传数据。发往 ipjudge.org 的请求只有一个：查询本机出口 IP 的判定（和你直接打开网站一样）。其余请求直接访问各平台的公开地址。

线上脚本和本仓库 `main` 分支一致，可以自己核对：

```bash
diff <(curl -sL ipjudge.org/cc) scripts/cc.sh && echo 一致
```

## 终端出口体检（Claude Code / Codex）

Claude Code、Codex 跑在终端里，只认 `HTTPS_PROXY` 这类环境变量，不一定走浏览器用的代理。浏览器检测显示美国住宅，终端却可能直连出去。

```bash
curl -sL ipjudge.org/cc | bash          # 中文
curl -sL ipjudge.org/en/cc | bash       # English
```

按 Claude Code 官方规则判断代理：只认 `https_proxy` / `HTTPS_PROXY` / `http_proxy` / `HTTP_PROXY` 和 `~/.claude/settings.json` 里的 `env`；**不支持 SOCKS，不读 `ALL_PROXY`**（[官方文档](https://code.claude.com/docs/en/corporate-proxy)）。

## MCP（给 AI Agent 用）

端点：`https://ipjudge.org/mcp`（Streamable HTTP，免费，不需要 key）

```bash
# Claude Code
claude mcp add --transport http ipjudge https://ipjudge.org/mcp
```

```json
// Cursor / Windsurf / 其他支持远程 MCP 的客户端
{ "mcpServers": { "ipjudge": { "url": "https://ipjudge.org/mcp" } } }
```

| 工具 | 说明 |
|---|---|
| `my_exit` | 判定**发起 MCP 请求的那台机器**的出口。Claude Code、Cursor 等本机客户端就是你的电脑；网页版 connector 由平台服务器发起请求，看到的是平台服务器的出口 |
| `check_ip` | 判定任意 IPv4 / IPv6：住宅 / 机房、纯净度 0–100、风险名单命中、四家 AI 是否接受 |
| `ai_availability` | 某国家 / 地区是否在 ChatGPT、Claude、Gemini、Muse 的官方支持名单里 |
| `service_status` | Claude、OpenAI、Cursor、GitHub、Cloudflare 等的官方实时状态 |

不带 key 时每个访客 10 分钟最多 40 次新查询；需要更多，在 [我的账户](https://ipjudge.org/account/) 创建 API key，加 `--header "Authorization: Bearer ipj_你的key"`。

## HTTP API

```bash
curl ipjudge.org/api/ip/8.8.8.8                       # JSON，无需 key
curl -H "Authorization: Bearer ipj_你的key" "https://ipjudge.org/api/v1/ip/8.8.8.8"
```

字段说明和配额见 [ipjudge.org/tools/api/](https://ipjudge.org/tools/api/)。展示结果时请注明「数据来自 ipjudge.org」并附链接；请勿批量扫描。

## 判定规则

规则全部公开：[ipjudge.org/method/](https://ipjudge.org/method/)。觉得判错了，到 [纠错页](https://ipjudge.org/corrections/) 提交，或在本仓库开 issue。

---

## English

**[ipjudge.org](https://ipjudge.org/en/)** is a neutral IP / network-exit checker. Before you use ChatGPT, Claude, Gemini or Meta Muse, see what your exit really looks like: residential or datacenter, whether the region is officially supported, DNS / WebRTC leaks, and whether your terminal takes the same route as your browser.

This repository holds **the parts that run on your machine**, so you can read them before piping to bash:

- [`scripts/cc.sh`](scripts/cc.sh) — Claude Code / Codex terminal exit check: `curl -sL ipjudge.org/en/cc | bash`
- [`scripts/check.sh`](scripts/check.sh) — server (VPS) check: `bash <(curl -Ls ipjudge.org/en/sh)`
- [`server.json`](server.json) — MCP server description, listed in the official MCP Registry as `org.ipjudge/ipjudge`

Both scripts are read-only: they install nothing, change nothing and upload nothing. The only request to ipjudge.org asks for the verdict on your own exit IP.

The terminal check follows Claude Code's documented proxy rules: only `https_proxy` / `HTTPS_PROXY` / `http_proxy` / `HTTP_PROXY` and the `env` block in `~/.claude/settings.json`. SOCKS is not supported and `ALL_PROXY` is not read ([docs](https://code.claude.com/docs/en/corporate-proxy)).

### MCP

Endpoint `https://ipjudge.org/mcp` (Streamable HTTP, free, no key needed):

```bash
claude mcp add --transport http ipjudge https://ipjudge.org/mcp
```

Tools: `my_exit` (the exit of whichever machine sends the MCP request — your computer for Claude Code / Cursor; the platform's servers for web connectors), `check_ip`, `ai_availability`, `service_status`. Without a key: 40 new lookups per visitor per 10 minutes. For more, create a key under [My account](https://ipjudge.org/en/account/) and send `Authorization: Bearer ipj_YOURKEY`.

### API, rules and corrections

- API docs: [ipjudge.org/en/tools/api/](https://ipjudge.org/en/tools/api/). Please credit “data from ipjudge.org” with a link; no bulk scanning.
- Scoring rules are public: [ipjudge.org/en/method/](https://ipjudge.org/en/method/).
- Wrong verdict? Use the [corrections page](https://ipjudge.org/en/corrections/) or open an issue here.

License: MIT
