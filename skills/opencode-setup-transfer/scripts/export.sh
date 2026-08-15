#!/usr/bin/env bash
# opencode 세팅 내보내기 — 화이트리스트, 비밀정보 제거, 절대경로 템플릿화
set -euo pipefail

# 주 용도는 "내 컴퓨터 → 내 다른 컴퓨터"라서 personal 이 기본이다.
# 남에게 줄 때만 --mode share 를 명시하게 해 실수로 개인정보가 나가지 않게 한다.
MODE="personal"
OUT=""
FORCE=0
USER_EXCLUDES=""
# 설정 폴더는 opencode 자신에게 묻는 것이 가장 정확하다.
# 일부 실행 환경(예: Orca 훅)이 OPENCODE_CONFIG_DIR 을 다른 곳으로 덮어써서,
# 그 값을 그대로 믿으면 엉뚱한 폴더를 내보내게 된다.

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

resolve_conf() {
  local p=""
  if command -v opencode >/dev/null 2>&1; then
    p="$(tmo 15 opencode debug paths 2>/dev/null | awk '$1=="config"{ $1=""; sub(/^ +/,""); print; exit }')"
  fi
  [ -n "$p" ] && [ -d "$p" ] && { printf '%s' "$p"; return; }
  printf '%s' "$HOME/.config/opencode"
}
CONF="$(resolve_conf)"
CLAUDE_SKILLS="$HOME/.claude/skills"

usage() {
  cat <<'EOF'
사용법: export.sh [--mode personal|share] [--out <파일경로>] [--exclude <이름>] [--force]

  --mode personal  (기본) 내 다른 컴퓨터로 이전 — 전역 AGENTS.md·연결 계정 정보 포함
  --mode share     남에게 배포 — 개인 지침·계정 정보 제외, 개인정보 발견 시 중단
  --out            결과 tar.gz 경로 (기본: ~/Desktop/opencode-setup-<mode>-<날짜>.tar.gz)
  --exclude <이름>  특정 파일·폴더 제외 (여러 번 사용 가능)
  --config-dir     설정 폴더를 직접 지정 (기본: opencode 가 알려주는 경로)
  --force          경고를 무시하고 강행

절대 담지 않는 것: ~/.local/share/opencode (auth.json = API 키, opencode.db = 대화 기록), node_modules
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --exclude) USER_EXCLUDES="$USER_EXCLUDES
${2:-}"; shift 2 ;;
    --config-dir) CONF="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 인자: $1" >&2; usage; exit 1 ;;
  esac
done

case "$MODE" in
  personal|share) ;;
  *) echo "오류: --mode personal 또는 --mode share 를 지정해야 합니다." >&2; usage; exit 1 ;;
esac
[ -d "$CONF" ] || { echo "오류: $CONF 가 없습니다. opencode 를 한 번 실행한 뒤 다시 시도하세요." >&2; exit 1; }

STAMP="$(date +%Y%m%d)"
OUT="${OUT:-$HOME/Desktop/opencode-setup-$MODE-$STAMP.tar.gz}"
HERE="$(cd "$(dirname "$0")" && pwd)"

STAGE="$(mktemp -d)/opencode-setup"
PAY="$STAGE/payload"
mkdir -p "$PAY"
EXCLUDE_FILE="$(dirname "$STAGE")/excludes.txt"
: > "$EXCLUDE_FILE"
printf '%s\n' "$USER_EXCLUDES" | grep -v '^$' >> "$EXCLUDE_FILE" || true

echo "== 1/6 파일 수집 (모드: $MODE)"
echo "  설정 폴더: $CONF"

BIG_LIMIT_MB=5
: > "$STAGE/SYMLINKS.md"

record_links() { # src label
  [ -d "$1" ] || return 0
  while IFS= read -r l; do
    tgt="$(readlink "$l" 2>/dev/null || echo '?')"
    name="$(basename "$l")"
    if [ ! -e "$l" ]; then
      echo "- [$2] \`$name\` ← \`$tgt\` (⚠️ 원본 없음 — 제외)" >> "$STAGE/SYMLINKS.md"; continue
    fi
    sz=$(du -sm -L "$l" 2>/dev/null | cut -f1); sz="${sz:-0}"
    if [ "$sz" -gt "$BIG_LIMIT_MB" ]; then
      echo "$name" >> "$EXCLUDE_FILE"
      echo "- [$2] \`$name\` ← \`$tgt\` (${sz}MB — **제외**, 원본 도구를 새 컴퓨터에 따로 설치하세요)" >> "$STAGE/SYMLINKS.md"
    else
      echo "- [$2] \`$name\` ← \`$tgt\` (내용 복사됨)" >> "$STAGE/SYMLINKS.md"
    fi
  done < <(find "$1" -maxdepth 2 -type l 2>/dev/null)
}

# 심볼릭 링크는 실체를 복사한다(-L). opencode 는 링크된 스킬 폴더를 따라가지 않으므로
# 실체를 넣어야 새 컴퓨터에서 스킬이 실제로 인식된다.
copy_dir() { # src dst
  [ -d "$1" ] || return 0
  mkdir -p "$2"
  rsync -aL --quiet --exclude-from="$EXCLUDE_FILE" \
    --exclude '.git/' --exclude 'node_modules/' --exclude '*.log' \
    --exclude '.DS_Store' --exclude '__pycache__/' --exclude '.pytest_cache/' \
    --exclude 'venv/' --exclude '.venv/' --exclude 'dist/' --exclude 'build/' \
    --exclude '.next/' --exclude 'coverage/' --exclude '*.pyc' \
    "$1"/ "$2"/ 2>/dev/null || cp -RL "$1"/. "$2"/ 2>/dev/null || true
}

# opencode 는 단수/복수 디렉터리명을 모두 인정한다
for d in agent agents command commands skill skills theme themes mode modes plugin plugins; do
  record_links "$CONF/$d" "$d"
  copy_dir "$CONF/$d" "$PAY/$d"
done

for f in opencode.json opencode.jsonc tui.json package.json; do
  [ -f "$CONF/$f" ] && cp "$CONF/$f" "$PAY/$f"
done

# opencode 가 자동으로 읽는 외부 스킬 (~/.claude/skills) — 강의 자산의 본체
if [ -d "$CLAUDE_SKILLS" ]; then
  record_links "$CLAUDE_SKILLS" "외부스킬"
  copy_dir "$CLAUDE_SKILLS" "$PAY/external-claude-skills"
fi

# 개인 카테고리
if [ "$MODE" = "personal" ]; then
  [ -f "$CONF/AGENTS.md" ] && cp "$CONF/AGENTS.md" "$PAY/AGENTS.md"
fi

find "$PAY" -type l -exec sh -c '[ -e "$1" ] || rm -f "$1"' _ {} \; 2>/dev/null || true

echo "== 2/6 opencode.json 비밀값 제거"
python3 - "$PAY" <<'PY'
import json, os, sys
pay = sys.argv[1]
p = os.path.join(pay, "opencode.json")
if not os.path.exists(p):
    print("  opencode.json 없음 — 건너뜀"); raise SystemExit
try:
    with open(p) as f: cfg = json.load(f)
except Exception as e:
    print("  ⚠️ opencode.json 파싱 실패:", e); raise SystemExit

hit = []
# 제공자 API 키
for name, prov in (cfg.get("provider") or {}).items():
    opts = prov.get("options") or {}
    for k in list(opts):
        if "key" in k.lower() or "token" in k.lower():
            opts[k] = "<<<REDACTED:provider.%s.options.%s>>>" % (name, k)
            hit.append("provider.%s.options.%s" % (name, k))
# MCP 헤더·환경변수
for name, srv in (cfg.get("mcp") or {}).items():
    for field in ("headers", "environment"):
        blk = srv.get(field) or {}
        for k, v in list(blk.items()):
            if isinstance(v, str) and not v.startswith("{env:") and (
                "key" in k.lower() or "token" in k.lower() or "auth" in k.lower() or "secret" in k.lower()):
                blk[k] = "<<<REDACTED:mcp.%s.%s.%s>>>" % (name, field, k)
                hit.append("mcp.%s.%s.%s" % (name, field, k))

with open(p, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

if hit:
    print("  자리표시자로 치환:", ", ".join(hit))
else:
    print("  치환할 비밀값 없음")

# 플러그인 재설치 안내
plugins = cfg.get("plugin") or []
lines = ["# 플러그인 복원 안내", "", "새 컴퓨터에서 아래를 실행하세요.", ""]
for item in plugins:
    mod = item[0] if isinstance(item, list) and item else item
    if isinstance(mod, str) and not mod.startswith((".", "file:")):
        lines.append("opencode plugin %s" % mod)
    elif isinstance(mod, str):
        lines.append("# 로컬 플러그인 %s — 파일이 함께 옮겨졌는지 확인하세요" % mod)
if len(lines) > 4:
    with open(os.path.join(pay, "PLUGINS.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
PY

echo "== 3/6 연결 서비스 목록 작성"
if [ "$MODE" = "personal" ]; then
  bash "$HERE/connections.sh" report full > "$STAGE/CONNECTIONS.md" 2>/dev/null || true
else
  bash "$HERE/connections.sh" report masked > "$STAGE/CONNECTIONS.md" 2>/dev/null || true
fi
echo "  $(grep -c '^- ' "$STAGE/CONNECTIONS.md" 2>/dev/null || echo 0)건 기록 (토큰은 담기지 않음)"

echo "== 4/6 절대경로 템플릿화 (\$HOME → {{HOME}})"
while IFS= read -r f; do
  if grep -Iq . "$f" 2>/dev/null; then
    perl -pi -e "s|\Q$HOME\E|{{HOME}}|g" "$f"
  fi
done < <(find "$PAY" -type f)

echo "== 5/6 비밀정보·개인정보 스캔"
SCAN="$(dirname "$STAGE")/secret-scan.txt"
RAW="$(dirname "$STAGE")/.raw.txt"
: > "$SCAN"; : > "$RAW"
PATTERN='(sk-[A-Za-z0-9]{16,}|sk-or-v1-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abp]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"?(api[_-]?key|access[_-]?token|client[_-]?secret)"?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,})'
FIXTURE='(/tests?/|/__tests__/|/fixtures?/|/site-packages/|/node_modules/|/examples?/|\.test\.|\.spec\.)'
grep -rIn -E "$PATTERN" "$PAY" 2>/dev/null | grep -v 'REDACTED' > "$RAW" || true
grep -v -E "$FIXTURE" "$RAW" > "$SCAN" || true
INFO="$(grep -c -E "$FIXTURE" "$RAW" || true)"
HITS=$(grep -c . "$SCAN" || true)
rm -f "$RAW"

[ "$INFO" -gt 0 ] && echo "  참고: 테스트·서드파티 샘플 ${INFO}건 (차단하지 않음)"
if [ "$HITS" -gt 0 ]; then
  echo "  ⚠️ 비밀정보 의심 ${HITS}건:"
  sed -e "s|$PAY/||" "$SCAN" | head -20
  if [ "$MODE" = "share" ] && [ "$FORCE" -ne 1 ]; then
    echo "  배포 모드에서는 중단합니다. --exclude <파일명> 으로 빼거나 값을 지운 뒤 다시 실행하세요." >&2
    exit 2
  fi
  echo "  personal 모드이므로 계속합니다. 이 아카이브를 남에게 주지 마세요."
else
  echo "  차단 대상 비밀정보 없음."
fi

if [ "$MODE" = "share" ]; then
  IDSCAN="$(dirname "$STAGE")/identity-scan.txt"
  : > "$IDSCAN"
  IDS=""
  for v in "$(whoami)" "$(hostname -s 2>/dev/null || true)" \
           "$(git config --global user.email 2>/dev/null || true)" \
           "$(git config --global user.name 2>/dev/null || true)"; do
    [ ${#v} -ge 4 ] && IDS="$IDS|$(printf '%s' "$v" | sed 's/[][\.*^$(){}?+|/]/\\&/g')"
  done
  IDS="${IDS#|}"
  if [ -n "$IDS" ]; then
    grep -rIn -E "($IDS)" "$PAY" 2>/dev/null | grep -v -E "$FIXTURE" > "$IDSCAN" || true
  fi
  IDHITS=$(grep -c . "$IDSCAN" || true)
  if [ "$IDHITS" -gt 0 ]; then
    echo "  ⚠️ 본인 식별정보 ${IDHITS}건:"
    sed -e "s|$PAY/||" "$IDSCAN" | head -20
    if [ "$FORCE" -ne 1 ]; then
      echo "  배포 모드에서는 중단합니다. --exclude <파일명> 으로 빼거나 값을 지운 뒤 다시 실행하세요." >&2
      exit 3
    fi
  else
    echo "  개인 식별정보 없음."
  fi
fi

echo "== 6/6 매니페스트 작성 및 압축"
{
  echo "# opencode 세팅 아카이브"
  echo
  echo "- 생성일: $(date '+%Y-%m-%d %H:%M')"
  echo "- 모드: $MODE"
  echo "- opencode: $(opencode --version 2>/dev/null || echo '확인 불가')"
  echo
  echo "## 포함된 항목"
  [ -f "$PAY/opencode.json" ] && echo "- opencode.json (비밀값 자리표시자 처리됨)"
  [ -f "$PAY/AGENTS.md" ] && echo "- AGENTS.md (전역 지침)"
  for d in agent agents command commands skill skills theme themes mode modes plugin plugins; do
    [ -d "$PAY/$d" ] && echo "- $d/ ($(find "$PAY/$d" -type f | wc -l | tr -d ' ')개 파일)"
  done
  [ -d "$PAY/external-claude-skills" ] && \
    echo "- external-claude-skills/ ($(ls "$PAY/external-claude-skills" | wc -l | tr -d ' ')개) → ~/.claude/skills 로 설치, opencode 가 자동 인식"
  [ -f "$PAY/PLUGINS.md" ] && echo "- PLUGINS.md (플러그인 재설치 명령)"
  echo "- CONNECTIONS.md (연결돼 있던 서비스 목록 — 토큰 없음)"
  echo
  echo "## 의도적으로 제외한 것"
  echo "- ~/.local/share/opencode 전체 (auth.json = API 키, opencode.db = 대화 기록, 로그)"
  echo "- node_modules (약 60MB — opencode 가 다시 설치)"
  echo "- GitHub·Firebase·Vercel 토큰 (계정에 묶여 있어 복사해도 동작하지 않음)"
  if [ -s "$STAGE/SYMLINKS.md" ]; then
    echo
    echo "## 심볼릭 링크였던 항목 ($(grep -c . "$STAGE/SYMLINKS.md")건)"
    echo "실체를 복사했습니다. 자세한 내용은 SYMLINKS.md 참고."
  fi
} > "$STAGE/MANIFEST.md"

if [ -s "$STAGE/SYMLINKS.md" ]; then
  { echo "# 원래 심볼릭 링크였던 항목"; echo;
    echo "opencode 는 링크된 스킬 폴더를 따라가지 않으므로 내용을 복사해 넣었습니다."; echo;
    cat "$STAGE/SYMLINKS.md"; } > "$STAGE/SYMLINKS.tmp"
  mv "$STAGE/SYMLINKS.tmp" "$STAGE/SYMLINKS.md"
else
  rm -f "$STAGE/SYMLINKS.md"
fi

for doc in "$STAGE/MANIFEST.md" "$STAGE/SYMLINKS.md" "$STAGE/CONNECTIONS.md"; do
  [ -f "$doc" ] && perl -pi -e "s|\Q$HOME\E|{{HOME}}|g" "$doc"
done

printf '%s\n' "$(printf '%s' "$HOME" | tr '/' '-')" > "$STAGE/.exporthome"
cp "$HERE/import.sh" "$STAGE/import.sh" 2>/dev/null || true
cp "$HERE/connections.sh" "$STAGE/connections.sh" 2>/dev/null || true
chmod +x "$STAGE/import.sh" "$STAGE/connections.sh" 2>/dev/null || true

mkdir -p "$(dirname "$OUT")"
tar -czf "$OUT" -C "$(dirname "$STAGE")" "$(basename "$STAGE")"
rm -rf "$(dirname "$STAGE")"

echo
echo "완료: $OUT"
echo "크기: $(du -h "$OUT" | cut -f1)"
echo
echo "새 컴퓨터에서:"
echo "  tar -xzf $(basename "$OUT") && cd opencode-setup && ./import.sh"
