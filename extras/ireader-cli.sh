#!/bin/bash
# Minimal helper for agents / scripts. Requires iReader.app registered for ireader://
# (open the app once after install). No Swift deps — just `open` + a status JSON file.
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  ireader-cli.sh export --path FILE.pdf --format md|txt|pdf|png|jpeg|outline|json [--pages 1-3,5] --out OUT [--status STATUS.json]
  ireader-cli.sh convert-word --paths 'a.docx|b.docx' --outdir DIR [--merge] [--status STATUS.json]
  ireader-cli.sh ping [--status STATUS.json]

说明:
  - 通过 macOS URL scheme 调用已安装的 iReader（ireader://…）
  - 默认把状态写到 --status（或 OUT 旁的 .ireader-status.json），脚本会轮询直到完成
  - format=png|jpeg 时 --out 必须是目录；其他格式 --out 是文件路径
USAGE
}

ACTION="${1:-}"
shift || true

PATH_ARG=""
FORMAT=""
PAGES=""
OUT=""
STATUS=""
PATHS=""
OUTDIR=""
MERGE=0
PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) PATH_ARG="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --pages) PAGES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --paths) PATHS="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    --merge) MERGE=1; shift ;;
    --password) PASSWORD="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

urlencode() {
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$1"
}

case "$ACTION" in
  export)
    [[ -n "$PATH_ARG" && -n "$FORMAT" && -n "$OUT" ]] || { usage; exit 2; }
    if [[ -z "$STATUS" ]]; then
      if [[ -d "$OUT" ]]; then STATUS="${OUT%/}/.ireader-status.json"
      else STATUS="${OUT}.ireader-status.json"; fi
    fi
    rm -f "$STATUS"
    Q="path=$(urlencode "$PATH_ARG")&format=$(urlencode "$FORMAT")&out=$(urlencode "$OUT")&status=$(urlencode "$STATUS")"
    [[ -n "$PAGES" ]] && Q+="&pages=$(urlencode "$PAGES")"
    [[ -n "$PASSWORD" ]] && Q+="&password=$(urlencode "$PASSWORD")"
    open "ireader://export?$Q"
    ;;
  convert-word)
    [[ -n "$PATHS" && -n "$OUTDIR" ]] || { usage; exit 2; }
    STATUS="${STATUS:-${OUTDIR%/}/.ireader-status.json}"
    rm -f "$STATUS"
    Q="paths=$(urlencode "$PATHS")&outdir=$(urlencode "$OUTDIR")&status=$(urlencode "$STATUS")"
    [[ "$MERGE" = 1 ]] && Q+="&merge=1"
    open "ireader://convert-word?$Q"
    ;;
  ping)
    STATUS="${STATUS:-/tmp/ireader-ping.json}"
    rm -f "$STATUS"
    open "ireader://ping?status=$(urlencode "$STATUS")"
    ;;
  *) usage; exit 2 ;;
esac

# Poll status file (up to ~60s)
for _ in $(seq 1 120); do
  if [[ -f "$STATUS" ]]; then
    cat "$STATUS"
    python3 - "$STATUS" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if d.get("ok") else 1)
PY
    exit $?
  fi
  sleep 0.5
done
echo '{"ok":false,"error":"等待 iReader 状态超时。请确认已安装并至少打开过一次 iReader。"}' >&2
exit 1
