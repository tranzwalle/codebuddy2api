# workbuddy2api

源自：[https://github.com/ShouZhuo0413/codebuddy2api](https://github.com/ShouZhuo0413/codebuddy2api)，把 **WorkBuddy / CodeBuddy**转成你本机可直接使用的 **OpenAI / Anthropic 兼容 API**。

适用场景：

- 用 **Codex CLI** 走 `/v1/responses`
- 用 **Claude Code / CC Switch** 走 `/v1/messages`
- 用 **Kimi Code** 走 custom registry（`api.json`）
- 用 **Cherry Studio / ZCode / LobeChat / NextChat / Open WebUI** 走 `/v1/chat/completions`

[English](#english) · [中文](#中文)

---

## 中文

### 这是什么

`workbuddy2api` 是一个本地协议转换器。它会读取你已经登录好的 WorkBuddy / CodeBuddy 桌面端凭据，转发到腾讯后端 `copilot.tencent.com`，然后在本地暴露这些接口：

- `POST /v1/chat/completions`
- `POST /v1/responses`
- `POST /v1/messages`
- `GET /v1/models`
- `GET /api.json`（Kimi Code custom registry，同 `/v1/models/api.json`）
- `GET /health`

它不负责登录，不模拟桌面端，也不替你执行工具。它只做三件事：

1. 读取本机登录态并注入鉴权头
2. 在 OpenAI / Anthropic 协议和腾讯后端协议之间转换
3. 对 `Codex CLI` 这类长上下文 agent 请求做后端友好的压缩投影

> 命名说明：项目对外名称现在叫 `workbuddy2api`。代码里仍保留部分历史命名，比如 `codebuddy2openai`、`CODEBUDDY2OPENAI_*`，目的是兼容旧配置和环境变量。
> 另外，GitHub 仓库路径当前也可能仍沿用 `codebuddy2openai`，这是仓库路径与项目展示名尚未完全统一，不影响使用。



### 你能用它做什么

- 把 WorkBuddy 订阅复用到 OpenAI 兼容客户端
- 让 Codex CLI 直接接腾讯后端，而不是只接 OpenAI 官方
- 让 Claude Code 通过 CC Switch 复用 WorkBuddy 支持的模型
- 让 Kimi Code 通过 `api.json` 批量导入 provider 和模型
- 保留原生 `tools` / `tool_calls` / 流式 SSE / 多轮工具调用



### 当前支持


| 客户端 / 协议                | 接口                     | 当前状态                           |
| ----------------------- | ---------------------- | ------------------------------ |
| OpenAI Chat Completions | `/v1/chat/completions` | 已支持                            |
| OpenAI Responses        | `/v1/responses`        | 已支持，适配 Codex CLI               |
| Anthropic Messages      | `/v1/messages`         | 已支持，适配 Claude Code / CC Switch |
| OpenAI Models           | `/v1/models`           | 已支持                            |
| Kimi Code Registry      | `/api.json`            | 已支持，custom registry 批量导入      |
| Health Check            | `/health`              | 已支持                            |


---



## 3 分钟上手



### 1. 前置条件

你需要先满足这 3 个条件：

1. 本机已经安装并登录 **WorkBuddy / CodeBuddy** 桌面端
2. 本机有 **Python 3.8+**
3. 已安装依赖 `fastapi`、`uvicorn`、`httpx`

默认会在这些位置寻找登录态：

- macOS: `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth/*.info`
- Windows: `%LOCALAPPDATA%\CodeBuddyExtension\Data\Public\auth\*.info`
- Linux: `~/.local/share/CodeBuddyExtension/Data/Public/auth/*.info`



### 2. 安装依赖

推荐用 `uv`：

```bash
git clone https://github.com/ShouZhuo0413/codebuddy2openai.git workbuddy2api
cd workbuddy2api

uv venv
uv pip install -r requirements.txt
```

也可以用虚拟环境：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

> 注意：无论是启动服务，还是执行 `python3 converter.py --help`，都必须先装依赖。



### 3. 启动

一键启动（推荐）：

```bash
./start.sh
```

或手动启动：

```bash
uv run converter.py --desensitize --log converter.log
```

或：

```bash
python3 converter.py --desensitize --log converter.log
```

`start.sh` 会自动创建虚拟环境、安装依赖，并带上 `--desensitize --log converter.log`。也支持 `./start.sh --daemon` 后台运行、`./start.sh --port 8788` 换端口。

看到监听 `http://127.0.0.1:8787` 就说明已经起来了。

### 4. 快速自检

```bash
curl http://127.0.0.1:8787/health
curl http://127.0.0.1:8787/v1/models
curl http://127.0.0.1:8787/api.json
```

如果这几条能通，说明本地服务、登录态、基本路由都没问题。

---



## 客户端接入



### Codex CLI

这是当前最推荐的接法。Codex CLI 走的是 `/v1/responses`，而不是 `/v1/chat/completions`。

推荐启动命令：

```bash
uv run converter.py --desensitize --log converter.log
```

把下面配置合并到 `~/.codex/config.toml`：

```toml
[model_providers.workbuddy]
name = "WorkBuddy (via local converter)"
base_url = "http://127.0.0.1:8787/v1"
wire_api = "responses"
env_key = "CODEBUDDY2OPENAI_KEY"

[profiles.workbuddy]
model = "glm-5.2"
model_provider = "workbuddy"
```

设置一个占位环境变量：

```bash
export CODEBUDDY2OPENAI_KEY=any-value
```

启动：

```bash
codex --profile workbuddy "你的任务描述"
```

补充说明：

- 推荐保留 `--desensitize`
- 当前 `/v1/responses` 默认已经会做投影压缩
- 如果你想尽量保留原始 system prompt，可试 `--desensitize --no-compact`
- `--desensitize --no-compact` 下若仍命中审核，当前实现会自动退回紧凑模式重试一次



### Claude Code / CC Switch

Claude Code 不走 OpenAI 协议，而是走 Anthropic Messages。

推荐启动命令：

```bash
uv run converter.py --desensitize --log converter.log
```

在 CC Switch 里配置：

```json
{
  "DeepSeek-V4-Pro": {
    "base_url": "http://127.0.0.1:8787/v1/messages",
    "api_key": "",
    "model": "deepseek-v4-pro"
  }
}
```

注意：

- 模型名必须填写腾讯后端支持的真实模型名
- 不做 Anthropic 模型名到腾讯模型名的自动映射
- Claude Code 场景强烈建议开启 `--desensitize`



### 其他 OpenAI 兼容客户端

适用于：

- Cherry Studio
- ZCode
- LobeChat
- NextChat
- Open WebUI
- 自己写的 OpenAI SDK 客户端

配置方式：

- Base URL: `http://127.0.0.1:8787/v1`
- API Key: 留空，或填你启动时设置的 `--api-key`
- 模型名: `glm-5.2` / `deepseek-v4-pro` / `kimi-k2.7` / `auto` 等



### Kimi Code（custom registry）

Kimi Code 支持通过 `api.json` 批量导入 provider，无需手动逐个配置模型。

服务启动后提供：

- `http://127.0.0.1:8787/api.json`
- `http://127.0.0.1:8787/v1/models/api.json`（同上）

导入命令：

```bash
kimi provider add http://127.0.0.1:8787/api.json --api-key any-value
```

说明：

- 未启用 `--api-key` 时，`--api-key` 可填任意值（Kimi CLI 要求提供该参数）
- 若启动时加了 `--api-key mysecret`，这里必须填同一个值
- 导入后 provider ID 为 `codebuddy`，模型别名形如 `codebuddy/glm-5.2`
- 在 TUI 里用 `/model` 或 `-m codebuddy/glm-5.2` 选择模型

`api.json` 返回 Kimi Code 所需的 registry 格式，例如：

```json
{
  "codebuddy": {
    "id": "codebuddy",
    "name": "CodeBuddy (local)",
    "api": "http://127.0.0.1:8787/v1",
    "type": "openai",
    "models": {
      "glm-5.2": {
        "id": "glm-5.2",
        "name": "GLM 5.2",
        "tool_call": true,
        "support_efforts": ["low", "medium", "high"],
        "default_effort": "high"
      }
    }
  }
}
```

思考模式依赖 `reasoning` 或 `support_efforts` 字段。模型列表来自 `models.json`（见下文），修改后需重启服务并重新导入 registry：

```bash
kimi provider remove codebuddy
kimi provider add http://127.0.0.1:8787/api.json --api-key any-value
```

更详细的本地使用说明见 [`使用文档.md`](./使用文档.md)。

---



## 常用命令



### 基本启动

```bash
python3 converter.py
python3 converter.py --desensitize
python3 converter.py --desensitize --log converter.log
python3 converter.py --api-key mysecret
python3 converter.py --port 9000
```



### 命令行参数


| 参数              | 默认值         | 说明                                           |
| --------------- | ----------- | -------------------------------------------- |
| `--host`        | `127.0.0.1` | 监听地址                                         |
| `--port`        | `8787`      | 监听端口                                         |
| `--api-key`     | 无           | 给本地客户端加一层鉴权                                  |
| `--log`         | 无           | 记录请求与响应日志                                    |
| `--desensitize` | 关           | 压缩运行时提示、去掉 tool description、零宽脱敏高风险关键词       |
| `--no-compact`  | 关           | 配合 `--desensitize` 使用，保留更完整的原始 system prompt |
| `--models-file` | 无           | 指定模型列表 JSON 文件（默认 `./models.json`）           |
| `--skip-check`  | 否           | 跳过启动预检                                       |




### curl 示例

```bash
curl http://127.0.0.1:8787/v1/models

curl http://127.0.0.1:8787/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-5.2","messages":[{"role":"user","content":"你好"}]}'

curl -N http://127.0.0.1:8787/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-5.2","stream":true,"messages":[{"role":"user","content":"数1到5"}]}'
```

---



## 日志与排障



### 推荐启动方式

```bash
uv run converter.py --desensitize --log converter.log
```



### 日志里能看到什么

每次请求都会带一个唯一 ID，常见日志包括：

- `REQUEST BODY`
- `RESPONSES → CHAT BODY`
- `RESPONSES PROJECTION`
- `RESPONSE BODY`
- `RESPONSE RAW SSE`
- `⚠️内容审核拦截`

其中 `RESPONSES PROJECTION` 会告诉你：

- 投影前后消息数
- 投影前后字符数
- tool schema 压缩量
- 是否丢掉了 harness 消息
- 是否保留了 anchor user



### 最常见问题



#### 找不到登录文件

说明桌面端没登录，或者登录目录不在默认路径。先确认桌面端已经真正完成登录。

#### 401

分两种：

- 本地 401：你启用了 `--api-key`，但客户端没带同一个 key
- 后端 401：腾讯 token 失效，尝试重新打开桌面端登录



#### 响应慢

先换快一点的模型，比如 `deepseek-v4-flash`。

#### 被“敏感内容”拦截

这是腾讯后端的内容审核，不一定是用户问题本身敏感，很多时候是 agent runtime 文本触发的，比如：

- `DoS`
- `exploit`
- `credential`
- `sandbox`
- `escalation`
- 竞争品牌词
- tool description 中的安全术语

建议排查顺序：

1. 开 `--log`
2. 看同一请求 ID 下的 `REQUEST BODY` 或 `RESPONSES → CHAT BODY`
3. 如果是 Codex CLI，再看 `RESPONSES PROJECTION`
4. 开 `--desensitize`
5. 如果还不稳，再尝试 `--desensitize --no-compact`

---



## Docker 部署

如果你更习惯用 Docker，可以直接用。

前提是把宿主机登录态目录挂进去，因为容器里拿不到桌面端 auth 文件。

### docker compose

先改 `docker-compose.yml` 里的 auth 挂载路径，再执行：

```bash
docker compose up -d --build
```



### docker run

```bash
docker build -t workbuddy2api .

docker run -d --name workbuddy2api -p 8787:8787 \
  -v ~/Library/Application Support/CodeBuddyExtension/Data/Public/auth:/data/auth:ro \
  -e CODEBUDDY_AUTH_DIR=/data/auth \
  workbuddy2api
```



### 相关环境变量


| 变量                     | 说明         |
| ---------------------- | ---------- |
| `CODEBUDDY_AUTH_DIR`   | 指定登录态目录    |
| `CODEBUDDY2OPENAI_KEY` | 本地 API Key |
| `CODEBUDDY2OPENAI_BASE_URL` | `api.json` 中 `api` 字段的公开地址 |
| `CODEBUDDY2OPENAI_MODELS` | 逗号分隔模型 ID，覆盖内置 / 文件列表 |
| `CODEBUDDY2OPENAI_MODELS_FILE` | 指定模型列表 JSON 文件路径 |
| `CODEBUDDY2OPENAI_LOG` | 日志路径       |


---



## 模型列表

腾讯后端没有公开的 models 拉取接口，因此 `/v1/models` 和 `/api.json` 展示的模型列表需要本地维护。

### 配置方式

推荐在项目根目录创建 `models.json`：

```bash
cp models.json.example models.json
```

示例：

```json
{
  "defaults": {
    "reasoning": true,
    "support_efforts": ["low", "medium", "high"],
    "default_effort": "high"
  },
  "models": [
    "glm-5.3",
    "glm-5.2",
    "deepseek-v4-flash"
  ]
}
```

也支持对象写法，单独指定展示名和思考模式：

```json
{
  "id": "glm-5.3",
  "name": "GLM 5.3",
  "tool_call": true,
  "reasoning": true,
  "support_efforts": ["low", "medium", "high"],
  "default_effort": "high"
}
```

其他来源（按优先级）：

1. 环境变量 `CODEBUDDY2OPENAI_MODELS=glm-5.2,deepseek-v4-flash`
2. 启动参数 `--models-file /path/to/models.json`
3. 本目录 `./models.json`
4. CodeBuddy CLI 的 `~/.codebuddy/models.json`
5. 内置默认列表

内置默认模型：

`glm-5.2`、`glm-5.1`、`glm-5v-turbo`、`kimi-k2.7`、`kimi-k2.6`、`kimi-k2.5`、`deepseek-v4-pro`、`deepseek-v4-flash`、`minimax-m3-pay`、`hy3-preview-agent`、`auto`

具体能不能用，取决于你的 WorkBuddy / CodeBuddy 订阅。即使列表里没写，只要后端支持，请求里也可以直接填真实 `model` 名称调用。

---



## 项目结构

```text
workbuddy2api/
├── converter.py
├── responses_adapter.py
├── responses_projection.py
├── anthropic_adapter.py
├── desensitize.py
├── start.sh
├── models.json.example
├── codex-codebuddy.example.toml
├── 使用文档.md
├── test_responses_adapter.py
├── test_anthropic_adapter.py
├── README.md
└── LICENSE
```

各文件作用：

- `converter.py`: 主入口，FastAPI 服务
- `responses_adapter.py`: OpenAI Responses ↔ Chat 适配
- `responses_projection.py`: Codex / agent 请求投影压缩
- `anthropic_adapter.py`: Anthropic Messages ↔ Chat 适配
- `desensitize.py`: 运行时文本压缩与零宽脱敏

---



## 致谢

本项目基于 [HanHan666666/codebuddy2openai](https://github.com/HanHan666666/codebuddy2openai) 的思路演进而来，感谢原作者的开源贡献。

## 免责声明

本项目仅用于个人学习与研究。与腾讯、WorkBuddy、CodeBuddy、OpenAI、Anthropic 无官方关联。请仅在你合法拥有订阅的前提下使用，并自行承担风险。

## 开源协议

[MIT](./LICENSE)

---



## English

`workbuddy2api` exposes your already logged-in **WorkBuddy / CodeBuddy** desktop session as local **OpenAI- and Anthropic-compatible APIs**.

Supported endpoints:

- `POST /v1/chat/completions`
- `POST /v1/responses`
- `POST /v1/messages`
- `GET /v1/models`
- `GET /api.json` (Kimi Code custom registry)
- `GET /health`

Recommended use cases:

- **Codex CLI** via `/v1/responses`
- **Claude Code / CC Switch** via `/v1/messages`
- **Kimi Code** via custom registry (`/api.json`)
- **Cherry Studio / ZCode / LobeChat / Open WebUI** via `/v1/chat/completions`



### Quick Start

```bash
git clone https://github.com/ShouZhuo0413/codebuddy2openai.git workbuddy2api
cd workbuddy2api

uv venv
uv pip install -r requirements.txt
./start.sh
```

Then verify:

```bash
curl http://127.0.0.1:8787/health
curl http://127.0.0.1:8787/v1/models
curl http://127.0.0.1:8787/api.json
```



### Codex CLI

Use `/v1/responses` and keep `--desensitize` enabled.

```toml
[model_providers.workbuddy]
name = "WorkBuddy (via local converter)"
base_url = "http://127.0.0.1:8787/v1"
wire_api = "responses"
env_key = "CODEBUDDY2OPENAI_KEY"

[profiles.workbuddy]
model = "glm-5.2"
model_provider = "workbuddy"
```

Run:

```bash
export CODEBUDDY2OPENAI_KEY=any-value
codex --profile workbuddy "your task"
```



### Claude Code / CC Switch

Use `/v1/messages`:

```json
{
  "DeepSeek-V4-Pro": {
    "base_url": "http://127.0.0.1:8787/v1/messages",
    "api_key": "",
    "model": "deepseek-v4-pro"
  }
}
```



### Kimi Code

Import via custom registry:

```bash
kimi provider add http://127.0.0.1:8787/api.json --api-key any-value
```

Model list is driven by `models.json`. After editing it, restart the service and re-import the registry.



### Notes

- `--desensitize` is recommended for both Codex CLI and Claude Code
- `/v1/responses` already applies backend-facing projection by default
- `--desensitize --no-compact` preserves more of the original system prompt
- if that still gets review-blocked, `/v1/responses` will retry once in compact mode



### CLI Options

```bash
python3 converter.py [--host HOST] [--port PORT] [--api-key KEY] [--log PATH] [--desensitize] [--skip-check]
```



### Disclaimer

For personal learning and research only. Not affiliated with Tencent, WorkBuddy, CodeBuddy, OpenAI, or Anthropic.

---

Keywords: codebuddy to openai · codebuddy2openai · workbuddy api proxy · workbuddy openai adapter · codex cli workbuddy · claude code workbuddy · tencent code assistant openai compatible api