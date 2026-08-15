#!/usr/bin/env bash
# opencode 세팅 가져오기 — 카테고리별 확인, 덮어쓰기 대신 병합
set -euo pipefail

# 기본은 완전 자동 적용. 새 컴퓨터에는 충돌할 것이 거의 없고,
# 있더라도 백업 후 덮어쓰므로 되돌릴 수 있다. --ask 로 항목별 확인 모드.
YES=1
SRC=""
# 각 도구의 설정 폴더는 이 컴퓨터를 기준으로 정한다.
# 도구가 아직 안 깔려 있어도 설정을 미리 넣어둘 수 있도록, 없으면 표준 경로를 쓴다.
dest_dir() {
  case "$1" in
    opencode)
      local p=""
      if command -v opencode >/dev/null 2>&1; then
        p="$(opencode debug paths </dev/null 2>/dev/null | awk '$1=="config"{ $1=""; sub(/^ +/,""); print; exit }')" || p=""
      fi
      printf '%s' "${p:-$HOME/.config/opencode}" ;;
    claude) printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    codex)  printf '%s' "${CODEX_HOME:-$HOME/.codex}" ;;
  esac
}
tool_label() {
  case "$1" in
    opencode) echo "opencode" ;; claude) echo "Claude Code" ;; codex) echo "codex" ;;
  esac
}
CONF="$(dest_dir opencode)"

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
  # 새 이름(ai-setup)과 옛 이름(opencode-setup) 모두 받아들인다
  SRC="$(find "$TMP" -maxdepth 2 -type d \( -name 'ai-setup' -o -name 'opencode-setup' \) | head -1)"
  [ -n "$SRC" ] || { echo "오류: 아카이브에서 세팅 폴더를 찾지 못했습니다." >&2; exit 1; }
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
      # 백업은 "도구/폴더" 구조로 남긴다. 도구마다 skills 폴더가 있어 이름만으로는 충돌한다.
      bkdir="$BACKUP/${tool:-unknown}/$(basename "$dst")"
      mkdir -p "$bkdir"
      cp -R "$dst"/. "$bkdir"/ 2>/dev/null || true
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

# ── 아카이브에 담긴 도구를 하나씩 적용한다 ────────────────────────
TOOLS=""
[ -f "$SRC/.tools" ] && TOOLS="$(cat "$SRC/.tools")"
if [ -z "$TOOLS" ]; then
  # 옛 형식(도구 폴더 없이 opencode 파일이 최상위)도 받아들인다
  for t in opencode claude codex; do [ -d "$WORK/$t" ] && TOOLS="$TOOLS $t"; done
  [ -z "$TOOLS" ] && [ -d "$WORK/skills" ] && { mkdir -p "$WORK/opencode"; mv "$WORK"/* "$WORK/opencode/" 2>/dev/null; TOOLS="opencode"; }
  [ -d "$WORK/external-claude-skills" ] && { mkdir -p "$WORK/claude"; mv "$WORK/external-claude-skills" "$WORK/claude/skills" 2>/dev/null; TOOLS="$TOOLS claude"; }
fi

APPLIED=""
for tool in $TOOLS; do
  TW="$WORK/$tool"
  [ -d "$TW" ] || continue
  DEST="$(dest_dir "$tool")"
  mkdir -p "$DEST"
  echo
  echo "═══ $(tool_label "$tool") → $DEST"

  for entry in "$TW"/*; do
    [ -e "$entry" ] || continue
    name="$(basename "$entry")"
    case "$name" in
      PLUGINS.txt) continue ;;                       # 안내용 파일
      opencode.json|opencode.jsonc|settings.json|config.toml) continue ;;  # 설정은 아래서 따로
    esac
    if [ -d "$entry" ]; then
      merge_dir "$entry" "$DEST/$name" "$name/"
    else
      if [ -e "$DEST/$name" ]; then
        echo
        echo "--- $name (이미 있음)"
        if ask "  덮어쓸까요? (기존본은 백업됩니다)"; then
          mkdir -p "$BACKUP/$tool"; cp "$DEST/$name" "$BACKUP/$tool/$name" 2>/dev/null || true
          cp "$entry" "$DEST/$name"; echo "  덮어썼습니다"
        else
          echo "  건너뜀"
        fi
      else
        cp "$entry" "$DEST/$name"
        echo
        echo "--- $name  복사 완료"
      fi
    fi
  done

  # 설정 파일 — 형식마다 다루는 법이 다르다
  apply_config() { # 원본파일 대상파일 병합가능여부
    local src="$1" dst="$2" mergeable="$3"
    [ -f "$src" ] || return 0
    echo
    echo "--- $(basename "$dst")"
    if [ ! -f "$dst" ]; then
      cp "$src" "$dst"
      echo "  복사 완료 (주석까지 그대로)"
      grep -o '<<<REDACTED:[^>]*>>>' "$dst" 2>/dev/null | sed 's/<<<REDACTED:/    직접 채워야 함: /; s/>>>//' | sort -u || true
      return 0
    fi
    mkdir -p "$BACKUP/$tool"; cp "$dst" "$BACKUP/$tool/$(basename "$dst")"
    if [ "$mergeable" = "json" ]; then
      ask "  기존 설정과 병합할까요?" || { echo "  건너뜀"; return 0; }
      python3 - "$src" "$dst" <<'PYCFG'
import json, os, re, sys
src, dst = sys.argv[1], sys.argv[2]
def load(path):
    raw = open(path, encoding='utf-8-sig').read()
    out, i, in_str, esc = [], 0, False, False
    while i < len(raw):
        c = raw[i]
        if in_str:
            out.append(c)
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
            i += 1; continue
        if c == '"': in_str = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < len(raw):
            if raw[i+1] == '/':
                while i < len(raw) and raw[i] != '\n': i += 1
                continue
            if raw[i+1] == '*':
                j = raw.find('*/', i + 2); i = len(raw) if j < 0 else j + 2; continue
        out.append(c); i += 1
    text = re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
    return json.loads(text) if text.strip() else {}
new = load(src); cur = load(dst) if os.path.exists(dst) else {}
def deep(a, b):
    out = dict(a)
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict): out[k] = deep(out[k], v)
        elif isinstance(v, list) and isinstance(out.get(k), list): out[k] = out[k] + [x for x in v if x not in out[k]]
        else: out[k] = v
    return out
merged = deep(cur, new)
red = []
def walk(o, p=""):
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, p + "." + k)
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, "%s[%d]" % (p, i))
    elif isinstance(o, str) and o.startswith("<<<REDACTED:"): red.append(p.lstrip("."))
walk(merged)
json.dump(merged, open(dst, "w"), indent=2, ensure_ascii=False)
print("  병합 완료 (기존본은 백업에 있습니다)")
for r in red: print("    직접 채워야 함:", r)
PYCFG
    else
      # TOML 은 안전한 자동 병합이 어렵다. 덮어쓰지 않고 나란히 둔다.
      cp "$src" "$dst.from-old-machine"
      echo "  이 컴퓨터에 이미 설정이 있어 덮어쓰지 않았습니다."
      echo "  옛 설정은 $(basename "$dst").from-old-machine 로 저장했습니다. 필요한 줄만 옮겨 쓰세요."
    fi
  }

  case "$tool" in
    opencode)
      SRC_CFG=""
      for cand in opencode.jsonc opencode.json; do [ -f "$TW/$cand" ] && { SRC_CFG="$cand"; break; }; done
      if [ -n "$SRC_CFG" ]; then
        DST_CFG=""
        for cand in opencode.jsonc opencode.json; do [ -f "$DEST/$cand" ] && { DST_CFG="$cand"; break; }; done
        apply_config "$TW/$SRC_CFG" "$DEST/${DST_CFG:-$SRC_CFG}" json
      fi ;;
    claude) apply_config "$TW/settings.json" "$DEST/settings.json" json ;;
    codex)  apply_config "$TW/config.toml"  "$DEST/config.toml"  toml ;;
  esac

  APPLIED="$APPLIED $tool"
done

echo
echo "== 적용 결과 확인"
for tool in $APPLIED; do
  case "$tool" in
    opencode)
      if command -v opencode >/dev/null 2>&1; then
        if tmo 20 opencode debug config </dev/null >/dev/null 2>&1; then
          echo "  opencode: 설정 정상 · 스킬 $(tmo 20 opencode debug skill </dev/null 2>/dev/null | grep -c '"name"' || echo '?')개 인식"
        else
          echo "  ⚠️ opencode: 설정을 읽지 못했습니다 → opencode debug config 로 확인하세요"
        fi
      else
        echo "  opencode: 아직 설치되지 않음 (설정만 넣어두었습니다)"
      fi ;;
    claude)
      if command -v claude >/dev/null 2>&1; then
        echo "  Claude Code: 설치됨 · 스킬 $(ls "$(dest_dir claude)/skills" 2>/dev/null | wc -l | tr -d ' ')개"
      else
        echo "  Claude Code: 아직 설치되지 않음 (설정만 넣어두었습니다)"
      fi ;;
    codex)
      if command -v codex >/dev/null 2>&1; then
        echo "  codex: 설치됨 · 스킬 $(ls "$(dest_dir codex)/skills" 2>/dev/null | wc -l | tr -d ' ')개"
      else
        echo "  codex: 아직 설치되지 않음 (설정만 넣어두었습니다)"
      fi ;;
  esac
done

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
WIZ="$CONF/skills/ai-setup-transfer/scripts/connect.sh"
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
N=1
for tool in $APPLIED; do
  case "$tool" in
    opencode)
      echo "$N. opencode auth login  — AI 제공자에 본인 키로 연결"; N=$((N+1))
      [ -f "$WORK/opencode/PLUGINS.txt" ] && { echo "$N. opencode 플러그인 설치:"; sed 's/^/     /' "$WORK/opencode/PLUGINS.txt"; N=$((N+1)); } ;;
    claude)
      [ -f "$WORK/claude/PLUGINS.txt" ] && { echo "$N. Claude Code 플러그인 설치:"; sed 's/^/     /' "$WORK/claude/PLUGINS.txt"; N=$((N+1)); } ;;
    codex)
      echo "$N. codex 로그인 (codex 실행 후 안내를 따르세요)"; N=$((N+1)) ;;
  esac
done
echo "$N. 설정 파일의 <<<REDACTED:...>>> 값 직접 채우기"; N=$((N+1))
echo "$N. 위 「아직 해야 할 것」의 서비스 로그인"; N=$((N+1))
echo "$N. 각 도구를 종료했다가 다시 실행 (설정은 시작할 때 한 번만 읽습니다)"
echo
echo "가져오기 전 상태 백업: $BACKUP"
