#!/usr/bin/env bash
# opencode 세팅 가져오기 — 카테고리별 확인, 덮어쓰기 대신 병합
set -euo pipefail

# 기본은 완전 자동 적용. 새 컴퓨터에는 충돌할 것이 거의 없고,
# 있더라도 백업 후 덮어쓰므로 되돌릴 수 있다. --ask 로 항목별 확인 모드.
YES=1
SRC=""
# 설정 폴더는 opencode 자신에게 묻는다 (OPENCODE_CONFIG_DIR 을 덮어쓰는 실행 환경이 있다)
resolve_conf() {
  local p=""
  if command -v opencode >/dev/null 2>&1; then
    p="$(opencode debug paths 2>/dev/null | awk '$1=="config"{ $1=""; sub(/^ +/,""); print; exit }')"
  fi
  [ -n "$p" ] && { printf '%s' "$p"; return; }
  printf '%s' "$HOME/.config/opencode"
}
CONF="$(resolve_conf)"
CLAUDE_SKILLS="$HOME/.claude/skills"

usage() {
  cat <<'EOF'
사용법: import.sh [--from <디렉터리|tar.gz>] [--ask]

  --from  아카이브 경로 (기본: 이 스크립트가 있는 디렉터리)
  --ask   항목마다 물어보기 (기본은 확인 없이 전부 적용)
  --yes   (기본) 확인 없이 전부 적용
  --config-dir  설정 폴더를 직접 지정
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from) SRC="${2:-}"; shift 2 ;;
    --yes) YES=1; shift ;;
    --ask) YES=0; shift ;;
    --config-dir) CONF="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; usage; exit 1 ;;
  esac
done

SRC="${SRC:-$(cd "$(dirname "$0")" && pwd)}"
if [ -f "$SRC" ]; then
  TMP="$(mktemp -d)"; tar -xzf "$SRC" -C "$TMP"
  SRC="$(find "$TMP" -maxdepth 2 -type d -name 'opencode-setup' | head -1)"
  [ -n "$SRC" ] || { echo "오류: 아카이브에서 opencode-setup 디렉터리를 찾지 못했습니다." >&2; exit 1; }
fi
PAY="$SRC/payload"
[ -d "$PAY" ] || { echo "오류: $PAY 가 없습니다." >&2; exit 1; }

echo "==================== 아카이브 정보 ===================="
[ -f "$SRC/MANIFEST.md" ] && cat "$SRC/MANIFEST.md"
echo "======================================================"
echo


# 외부 CLI 는 로그인 대기·네트워크로 멈출 수 있다. 반드시 제한 시간을 건다.
tmo() { # 초 명령...
  local s="$1"; shift
  "$@" &
  local p=$!
  ( sleep "$s"; kill -9 "$p" 2>/dev/null ) &
  local w=$!
  wait "$p" 2>/dev/null
  local rc=$?
  kill -9 "$w" 2>/dev/null
  wait "$w" 2>/dev/null
  return $rc
}

ask() {
  [ "$YES" -eq 1 ] && return 0
  local reply
  printf "%s [y/N] " "$1"
  read -r reply </dev/tty || reply=""
  [[ "$reply" =~ ^[Yy]$ ]]
}

BACKUP="$CONF/backups/import-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP" "$CONF"

if [ "$YES" -eq 1 ]; then
  echo "== 자동 적용 모드 (항목별로 확인하려면 --ask)"
fi
echo "== 절대경로 복원 ({{HOME}} → $HOME)"
WORK="$(mktemp -d)/payload"
mkdir -p "$WORK"; cp -R "$PAY"/. "$WORK"/
while IFS= read -r f; do
  if grep -Iq . "$f" 2>/dev/null; then
    perl -pi -e "s|\{\{HOME\}\}|$HOME|g" "$f"
  fi
done < <(find "$WORK" -type f)

merge_dir() { # src dst label
  local src="$1" dst="$2" label="$3"
  [ -d "$src" ] || return 0
  local total=0
  local nconf=0
  local conflist=""
  local f=""
  local rel=""
  total=$(find "$src" -type f | wc -l | tr -d ' ')
  [ "$total" -eq 0 ] && return 0
  echo
  echo "--- $label (${total}개 파일)"
  while IFS= read -r f; do
    rel="${f#$src/}"
    [ -e "$dst/$rel" ] && conflist="$conflist$rel"$'\n'
  done < <(find "$src" -type f)
  nconf=$(printf '%s' "$conflist" | grep -c . || true)
  if [ "$nconf" -gt 0 ]; then
    echo "  이미 존재하는 파일 ${nconf}개:"
    printf '%s' "$conflist" | head -10 | sed 's/^/    /'
    [ "$nconf" -gt 10 ] && echo "    ... 외 $(( nconf - 10 ))개"
  fi
  if ask "  $label 을(를) 가져올까요?"; then
    if [ "$nconf" -gt 0 ] && ask "  기존 파일을 덮어쓸까요? (아니오 = 없는 것만 추가)"; then
      mkdir -p "$BACKUP/$(basename "$dst")"
      cp -R "$dst"/. "$BACKUP/$(basename "$dst")"/ 2>/dev/null || true
      mkdir -p "$dst"; cp -R "$src"/. "$dst"/
      echo "  덮어쓰기 완료 (기존본 백업: $BACKUP)"
    else
      mkdir -p "$dst"
      (cd "$src" && find . -type f -print0 | while IFS= read -r -d '' rel; do
        [ -e "$dst/$rel" ] || { mkdir -p "$dst/$(dirname "$rel")"; cp "$rel" "$dst/$rel"; }
      done)
      echo "  새 파일만 추가 완료"
    fi
  else
    echo "  건너뜀"
  fi
}

for d in agent agents command commands skill skills theme themes mode modes plugin plugins; do
  merge_dir "$WORK/$d" "$CONF/$d" "$d/"
done

# opencode 가 자동으로 읽는 외부 스킬
merge_dir "$WORK/external-claude-skills" "$CLAUDE_SKILLS" "외부 스킬 (~/.claude/skills)"

if [ -f "$WORK/AGENTS.md" ]; then
  echo
  echo "--- 전역 지침 (AGENTS.md)"
  [ -f "$CONF/AGENTS.md" ] && echo "  기존 AGENTS.md 가 있습니다. 덮어쓰면 사라집니다(백업은 남습니다)."
  if ask "  가져올까요?"; then
    [ -f "$CONF/AGENTS.md" ] && cp "$CONF/AGENTS.md" "$BACKUP/AGENTS.md"
    cp "$WORK/AGENTS.md" "$CONF/AGENTS.md"; echo "  완료"
  fi
fi

# 플러그인 의존성(package.json)을 병합한다.
# opencode 는 시작할 때 여기 적힌 모듈을 스스로 설치하므로, 이 파일만 맞으면 플러그인이 자동 복원된다.
if [ -f "$WORK/package.json" ]; then
  echo
  echo "--- 플러그인 의존성 (package.json)"
  if ask "  병합할까요?"; then
    [ -f "$CONF/package.json" ] && cp "$CONF/package.json" "$BACKUP/package.json"
    python3 - "$WORK/package.json" "$CONF/package.json" <<'PYP'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
new = json.load(open(src))
cur = json.load(open(dst)) if os.path.exists(dst) else {}
deps = dict(cur.get("dependencies") or {})
added = []
for k, v in (new.get("dependencies") or {}).items():
    if k not in deps:
        deps[k] = v
        added.append(k)
cur["dependencies"] = deps
json.dump(cur, open(dst, "w"), indent=2)
if added:
    print("  추가된 플러그인 %d개: %s" % (len(added), ", ".join(added)))
    print("  → opencode 를 다시 실행하면 자동으로 설치됩니다.")
else:
    print("  새로 추가할 플러그인 없음")
PYP
  fi
fi

if [ -f "$WORK/opencode.json" ]; then
  echo
  echo "--- opencode.json"
  if ask "  병합할까요? (기존 값은 백업 후, 겹치는 키는 새 값으로)"; then
    [ -f "$CONF/opencode.json" ] && cp "$CONF/opencode.json" "$BACKUP/opencode.json"
    python3 - "$WORK/opencode.json" "$CONF/opencode.json" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
new = json.load(open(src))
cur = json.load(open(dst)) if os.path.exists(dst) else {}

def deep(a, b):
    out = dict(a)
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep(out[k], v)
        elif isinstance(v, list) and isinstance(out.get(k), list):
            out[k] = out[k] + [x for x in v if x not in out[k]]
        else:
            out[k] = v
    return out

merged = deep(cur, new)
red = []
def walk(o, p=""):
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, p + "." + k)
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, "%s[%d]" % (p, i))
    elif isinstance(o, str) and o.startswith("<<<REDACTED:"):
        red.append(p.lstrip("."))
walk(merged)
json.dump(merged, open(dst, "w"), indent=2, ensure_ascii=False)
print("  병합 완료")
if red:
    print("  ⚠️ 직접 채워야 하는 값:")
    for r in red: print("    ", r)
PY
  fi
fi

echo
echo "== opencode 설정 검증"
if command -v opencode >/dev/null 2>&1; then
  if tmo 20 opencode debug config >/dev/null 2>&1; then
    echo "  설정이 정상적으로 읽힙니다."
    echo "  인식된 스킬: $(tmo 20 opencode debug skill 2>/dev/null | grep -c '"name"' || echo '확인 불가')개"
  else
    echo "  ⚠️ opencode 가 설정을 읽지 못했습니다. 아래로 원인을 확인하세요:"
    echo "     opencode debug config"
  fi
else
  echo "  opencode 가 아직 설치되지 않았습니다."
fi

echo
if [ -f "$SRC/CONNECTIONS.md" ]; then
  echo "== 연결해야 할 서비스"
  sed 's/^/  /' "$SRC/CONNECTIONS.md"
  echo
fi

if [ -f "$SRC/connections.sh" ]; then
  bash "$SRC/connections.sh" setup || true
fi

# 연결 마법사 안내 — 터미널이 낯선 사람은 이걸로 손 잡고 진행한다
WIZ="$CONF/skills/opencode-setup-transfer/scripts/connect.sh"
if [ -f "$WIZ" ]; then
  echo
  echo "== 서비스 연결을 도와드립니다"
  echo "  GitHub·Firebase·Vercel·Supabase·Netlify 를 하나씩 안내받으려면:"
  echo "     $WIZ wizard"
  echo "  지금 상태만 보려면:"
  echo "     $WIZ check"
fi

echo
echo "==================== 남은 작업 ===================="
echo "1. opencode auth login  — AI 제공자에 본인 API 키로 연결"
[ -f "$WORK/PLUGINS.md" ] && { echo "2. 플러그인 설치:"; sed 's/^/     /' "$WORK/PLUGINS.md"; }
echo "3. opencode.json 의 <<<REDACTED:...>>> 값 직접 채우기"
echo "4. 위 「아직 해야 할 것」의 로그인 명령 실행"
echo "5. opencode 를 종료했다가 다시 실행 (설정은 시작할 때 한 번만 읽습니다)"
echo
echo "가져오기 전 상태 백업: $BACKUP"
