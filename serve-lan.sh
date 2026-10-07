#!/usr/bin/env bash
set -euo pipefail

SITE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-8080}"
KILL_OCCUPANT=0

for arg in "$@"; do
  case "$arg" in
    -k|--kill) KILL_OCCUPANT=1 ;;
    -h|--help)
      echo "用法: $0 [-k|--kill]"
      echo "  -k, --kill  端口被占用时，先结束占用该端口的旧服务再启动"
      echo "  PORT=<端口> 可覆盖默认端口（默认 8080）"
      exit 0
      ;;
    *)
      echo "未知参数: $arg（用 --help 查看用法）" >&2
      exit 2
      ;;
  esac
done

cd "$SITE_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "未找到 python3，请先安装 Python 3。" >&2
  exit 1
fi

port_free() {
  python3 - "$1" <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("0.0.0.0", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
PY
}

occupants() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnpH "sport = :${PORT}" 2>/dev/null | sed -n 's/.*users:((\(.*\))).*/\1/p'
  fi
}

if ! port_free "$PORT"; then
  echo "端口 ${PORT} 已被占用，无法启动。" >&2
  info="$(occupants)"
  if [ -n "$info" ]; then
    echo "占用者: ${info}" >&2
  fi
  if [ "$KILL_OCCUPANT" -eq 1 ]; then
    echo "已指定 --kill，正在结束占用进程..." >&2
    pkill -f "serve_range\.py ${PORT}" 2>/dev/null || true
    pkill -f "http\.server ${PORT}" 2>/dev/null || true
    sleep 1
    if ! port_free "$PORT"; then
      echo "端口 ${PORT} 仍未释放，请手动检查后再试。" >&2
      exit 1
    fi
    echo "端口 ${PORT} 已释放。" >&2
  else
    echo "提示: 用 '$0 --kill' 自动结束旧服务，或手动执行 'kill <PID>'。" >&2
    exit 1
  fi
fi

LAN_IPS="$(hostname -I 2>/dev/null || true)"

echo "γ-Art 局域网服务启动中..."
echo "本机访问: http://127.0.0.1:${PORT}/"
for ip in $LAN_IPS; do
  case "$ip" in
    172.17.*) continue ;;
  esac
  echo "局域网访问: http://${ip}:${PORT}/"
done
echo "保持此终端窗口开启；按 Ctrl+C 停止服务。"
echo

exec python3 "$SITE_DIR/serve_range.py" "$PORT"
