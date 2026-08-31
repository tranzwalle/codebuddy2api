#!/usr/bin/env bash
# 一键启动本地 OpenAI / Anthropic 兼容转换器。
# 用法：
#   ./start.sh              前台运行（Ctrl+C 停止）
#   ./start.sh --daemon     后台运行
#   ./start.sh --port 8788  改端口
#   ./start.sh --stop       停止后台进程
# 其余参数原样传给 converter.py。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

HOST="${CODEBUDDY2API_HOST:-127.0.0.1}"
PORT="${CODEBUDDY2API_PORT:-8787}"
DAEMON=0
STOP=0
FORWARD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop)
      STOP=1
      shift
      ;;
    --daemon|-d)
      DAEMON=1
      shift
      ;;
    --port)
      PORT="$2"
      FORWARD+=(--port "$2")
      shift 2
      ;;
    --host)
      HOST="$2"
      FORWARD+=(--host "$2")
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
一键启动 codebuddy2api（读取本机 CodeBuddy 登录态，默认监听 127.0.0.1:8787）

  ./start.sh                 前台运行
  ./start.sh --daemon        后台运行，PID 写入 converter.pid
  ./start.sh --stop          停止后台进程
  ./start.sh --port 8788     指定端口
  ./start.sh -- --api-key x  额外参数传给 converter.py

环境变量：CODEBUDDY2API_HOST / CODEBUDDY2API_PORT / CODEBUDDY_AUTH_DIR
EOF
      exit 0
      ;;
    --)
      shift
      FORWARD+=("$@")
      break
      ;;
    *)
      FORWARD+=("$1")
      shift
      ;;
  esac
done

has_port_arg=0
for a in "${FORWARD[@]+"${FORWARD[@]}"}"; do
  if [[ "$a" == "--port" ]]; then
    has_port_arg=1
    break
  fi
done
if [[ $has_port_arg -eq 0 ]]; then
  FORWARD=(--port "$PORT" "${FORWARD[@]+"${FORWARD[@]}"}")
fi

health_url="http://${HOST}:${PORT}/health"

already_up() {
  python3 - "$health_url" <<'PY' 2>/dev/null
import json, sys, urllib.request
url = sys.argv[1]
try:
    with urllib.request.urlopen(url, timeout=2) as r:
        data = json.loads(r.read().decode())
    sys.exit(0 if data.get("status") == "ok" else 1)
except Exception:
    sys.exit(1)
PY
}

if [[ $STOP -eq 1 ]]; then
  if already_up && command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN || true)"
    if [[ -n "$pids" ]]; then
      # 可能有多个 PID（uv 与 python）
      echo "$pids" | xargs kill 2>/dev/null || true
      echo "已停止 ${HOST}:${PORT}（PID $(echo "$pids" | tr '\n' ' '))"
    fi
  elif [[ -f converter.pid ]]; then
    pid="$(cat converter.pid)"
    kill "$pid" 2>/dev/null || true
    echo "已停止 PID $pid"
  else
    echo "服务未在 ${HOST}:${PORT} 运行"
  fi
  rm -f converter.pid
  exit 0
fi

if already_up; then
  echo "服务已在运行：$health_url"
  echo "  GET  /v1/models"
  echo "  GET  /api.json"
  echo "  POST /v1/chat/completions"
  echo "  POST /v1/responses"
  echo "  POST /v1/messages"
  exit 0
fi

if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "端口 ${HOST}:${PORT} 已被占用，且 /health 不是本服务。" >&2
    echo "结束占用进程，或换端口： ./start.sh --port 8788" >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
    exit 1
  fi
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "未找到 uv，请先安装：https://docs.astral.sh/uv/" >&2
  echo "或手动：python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
  exit 1
fi

if [[ ! -d .venv ]]; then
  echo "创建虚拟环境…"
  uv venv
fi

if ! .venv/bin/python -c "import fastapi, uvicorn, httpx" >/dev/null 2>&1; then
  echo "安装依赖…"
  uv pip install -r requirements.txt
fi

ARGS=(converter.py --desensitize --log converter.log "${FORWARD[@]}")

echo "启动 http://${HOST}:${PORT} （--desensitize --log converter.log）"
if [[ $DAEMON -eq 1 ]]; then
  nohup uv run "${ARGS[@]}" >>converter.log 2>&1 &
  echo $! > converter.pid
  echo "后台 PID $(cat converter.pid)，日志 converter.log"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if already_up; then
      echo "就绪：$health_url"
      exit 0
    fi
    sleep 0.3
  done
  echo "已拉起进程，但尚未通过 /health。查看 converter.log" >&2
  exit 1
fi

exec uv run "${ARGS[@]}"
