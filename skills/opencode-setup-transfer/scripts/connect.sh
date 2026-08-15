#!/usr/bin/env bash
# 백엔드·배포 서비스 연결 마법사
#
# GitHub · Firebase · Vercel · Supabase · Netlify 를 한 번에 하나씩 연결한다.
# 브라우저를 대신 열어주고, 그 화면에서 무엇을 눌러야 하는지 알려주고,
# 끝나면 정말 됐는지 자동으로 확인한다.
#
# 로그인을 대신해 주지는 않는다. 비밀번호와 2단계 인증은 본인만 다뤄야 하고,
# 화면이 조금만 바뀌어도 깨지기 때문이다. 대신 길을 끝까지 안내한다.
set -uo pipefail

MODE="${1:-wizard}"   # wizard | check
ONLY="${2:-}"         # github | firebase | vercel | supabase | netlify

have() { command -v "$1" >/dev/null 2>&1; }

tmo() { # 초 명령... — 로그인 대기로 멈추지 않게
  local s="$1"; shift
  "$@" & local p=$!
  ( sleep "$s"; kill -9 "$p" 2>/dev/null ) & local w=$!
  wait "$p" 2>/dev/null; local rc=$?
  kill -9 "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return $rc
}

# 브라우저 열기 — 맥·리눅스·WSL 모두 대응
open_url() {
  local url="$1"
  if have open; then open "$url" >/dev/null 2>&1 && return 0; fi
  if have wslview; then wslview "$url" >/dev/null 2>&1 && return 0; fi
  if have xdg-open; then xdg-open "$url" >/dev/null 2>&1 && return 0; fi
  if have powershell.exe; then powershell.exe -c "Start-Process '$url'" >/dev/null 2>&1 && return 0; fi
  return 1
}

C_B=$'\033[1m'; C_D=$'\033[2m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
[ -t 1 ] || { C_B=""; C_D=""; C_G=""; C_Y=""; C_R=""; C_0=""; }

ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$C_R" "$C_0" "$1"; }
info() { printf '  %s\n' "$1"; }
dim()  { printf '  %s%s%s\n' "$C_D" "$1" "$C_0"; }

# /dev/tty 는 존재해도 열리지 않는 환경이 있다(백그라운드 실행 등).
# 실제로 한 번 열어보고 결과를 기억한다. 서브셸 안에서 시도해 오류 메시지가 새지 않게 한다.
if ( exec 3</dev/tty ) 2>/dev/null; then HAS_TTY=1; else HAS_TTY=0; fi
has_tty() { [ "$HAS_TTY" -eq 1 ]; }

pause() { # 사용자가 브라우저에서 작업을 마칠 때까지 기다린다
  has_tty || return 0
  printf '\n  %s다 하셨으면 엔터를 누르세요%s (건너뛰려면 s + 엔터) ' "$C_B" "$C_0"
  local r; read -r r </dev/tty 2>/dev/null || r=""
  [ "$r" = "s" ] && return 1
  return 0
}

confirm() {
  has_tty || { printf '  %s [건너뜀 — 터미널에서 실행하세요]\n' "$1"; return 1; }
  printf '  %s [y/N] ' "$1"
  local r; read -r r </dev/tty 2>/dev/null || r=""
  [[ "$r" =~ ^[Yy]$ ]]
}

# ── OS 판별: 설치 명령을 다르게 안내한다 ────────────────────────────
OS="linux"
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  grep -qi microsoft /proc/version 2>/dev/null && OS="wsl" || OS="linux" ;;
esac

install_hint() { # 도구이름
  case "$1" in
    gh)       [ "$OS" = mac ] && echo "brew install gh" || echo "sudo apt install gh" ;;
    firebase) echo "npm install -g firebase-tools" ;;
    vercel)   echo "npm install -g vercel" ;;
    supabase) [ "$OS" = mac ] && echo "brew install supabase/tap/supabase" || echo "npm install -g supabase" ;;
    netlify)  echo "npm install -g netlify-cli" ;;
  esac
}

# ── 서비스별 상태 확인 ──────────────────────────────────────────────
# CLI 출력에 섞인 색상 코드를 걷어낸다. 안 걷으면 계정명에 39m 같은 찌꺼기가 붙는다.
strip_ansi() { sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g'; }

status_of() { # 서비스 → "계정명" 출력, 미연결이면 빈 문자열
  case "$1" in
    github)   tmo 8  gh auth status 2>&1 | strip_ansi | grep -oE 'account [A-Za-z0-9_-]+' | awk '{print $2}' | paste -sd, - ;;
    firebase) tmo 12 firebase login:list 2>/dev/null | strip_ansi | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | head -1 ;;
    vercel)   tmo 12 vercel whoami 2>/dev/null | strip_ansi | tail -1 | tr -d '[:space:]' | grep -E '^[A-Za-z0-9_-]{1,39}$' ;;
    supabase) tmo 12 supabase projects list 2>/dev/null | grep -qE '\|' && echo "연결됨" ;;
    netlify)  tmo 12 netlify status 2>/dev/null | strip_ansi | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | head -1 ;;
  esac
}

cli_of() {
  case "$1" in
    github) echo gh ;; firebase) echo firebase ;; vercel) echo vercel ;;
    supabase) echo supabase ;; netlify) echo netlify ;;
  esac
}
name_of() {
  case "$1" in
    github) echo "GitHub" ;; firebase) echo "Firebase" ;; vercel) echo "Vercel" ;;
    supabase) echo "Supabase" ;; netlify) echo "Netlify" ;;
  esac
}
why_of() {
  case "$1" in
    github)   echo "코드를 저장하고 버전을 관리하는 곳" ;;
    firebase) echo "앱의 데이터베이스와 로그인 기능을 맡는 곳" ;;
    vercel)   echo "만든 웹사이트를 인터넷에 올리는 곳" ;;
    supabase) echo "데이터베이스(PostgreSQL)를 빌려 쓰는 곳" ;;
    netlify)  echo "웹사이트를 인터넷에 올리는 곳 (Vercel 과 비슷한 역할)" ;;
  esac
}

# ── 서비스별 화면 안내 ──────────────────────────────────────────────
guide_of() {
  case "$1" in
    github)
      cat <<'EOG'
  터미널에 이런 화면이 차례로 나옵니다. 방향키로 고르고 엔터를 누르세요.

    ? What account do you want to log into?
        > GitHub.com              ← 이걸 고릅니다

    ? What is your preferred protocol?
        > HTTPS                   ← 이걸 고릅니다

    ? Authenticate Git with your GitHub credentials?  → Y

    ? How would you like to authenticate?
        > Login with a web browser ← 이걸 고릅니다

  그러면 여덟 자리 코드가 나옵니다.  예: A1B2-C3D4
  코드를 복사하고 엔터를 누르면 브라우저가 열립니다.
  브라우저 칸에 그 코드를 붙여넣고 Continue → Authorize 를 누르세요.
EOG
      ;;
    firebase)
      cat <<'EOG'
  브라우저에 구글 로그인 화면이 뜹니다.

    1. 앱에서 쓸 구글 계정을 고릅니다
    2. "Firebase CLI가 다음 권한을 요청합니다" → 허용 을 누릅니다
    3. "Firebase CLI Login Successful" 이라고 나오면 성공입니다

  ※ 계정이 여러 개면 반드시 프로젝트를 만든 그 계정으로 로그인하세요.
EOG
      ;;
    vercel)
      cat <<'EOG'
  터미널에서 로그인 방법을 고르라고 합니다.

    > Continue with GitHub      ← 깃허브로 가입했다면 이걸 고릅니다
      Continue with Email

  브라우저가 열리면 Authorize 또는 확인 을 누르세요.
  터미널에 "Success! GitHub authentication complete" 가 나오면 끝입니다.
EOG
      ;;
    supabase)
      cat <<'EOG'
  브라우저에 Supabase 로그인 화면이 열립니다.

    1. 로그인하면 "Generate access token" 화면이 나옵니다
    2. Generate token 을 누릅니다
    3. 화면에 나온 긴 문자열을 복사합니다
    4. 터미널로 돌아와 붙여넣고 엔터

  ※ 붙여넣어도 화면에 글자가 안 보이는 것이 정상입니다.
EOG
      ;;
    netlify)
      cat <<'EOG'
  브라우저에 Netlify 인증 화면이 열립니다.

    1. 로그인합니다 (깃허브 계정으로도 됩니다)
    2. "Authorize" 버튼을 누릅니다
    3. "You are now logged into your Netlify account" 가 나오면 성공입니다
EOG
      ;;
  esac
}

signup_url() {
  case "$1" in
    github) echo "https://github.com/signup" ;;
    firebase) echo "https://console.firebase.google.com" ;;
    vercel) echo "https://vercel.com/signup" ;;
    supabase) echo "https://supabase.com/dashboard" ;;
    netlify) echo "https://app.netlify.com/signup" ;;
  esac
}

login_cmd() {
  case "$1" in
    github) echo "gh auth login" ;;
    firebase) echo "firebase login" ;;
    vercel) echo "vercel login" ;;
    supabase) echo "supabase login" ;;
    netlify) echo "netlify login" ;;
  esac
}

SERVICES="github firebase vercel supabase netlify"
[ -n "$ONLY" ] && SERVICES="$ONLY"

# ── 상태만 보기 ─────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
  echo "${C_B}서비스 연결 상태${C_0}"
  echo
  for svc in $SERVICES; do
    cli="$(cli_of "$svc")"; nm="$(name_of "$svc")"
    if ! have "$cli"; then
      printf '  %-10s %s설치 안 됨%s   %s\n' "$nm" "$C_D" "$C_0" "$(install_hint "$cli")"
      continue
    fi
    acct="$(status_of "$svc")"
    if [ -n "$acct" ]; then printf '  %-10s %s연결됨%s  %s\n' "$nm" "$C_G" "$C_0" "$acct"
    else printf '  %-10s %s로그인 필요%s   %s\n' "$nm" "$C_Y" "$C_0" "$(login_cmd "$svc")"; fi
  done
  echo
  dim "연결을 도와드릴까요?  connect.sh wizard"
  exit 0
fi

# ── 마법사 ──────────────────────────────────────────────────────────
cat <<EOF
${C_B}백엔드·배포 서비스 연결 도우미${C_0}

쓰시는 서비스만 하나씩 연결합니다. 안 쓰는 것은 건너뛰셔도 됩니다.
비밀번호는 이 도구가 볼 수 없습니다. 로그인은 본인 브라우저에서만 이루어집니다.

EOF

TOTAL=$(printf '%s\n' $SERVICES | grep -c .)
N=0
DONE=""; SKIPPED=""

for svc in $SERVICES; do
  N=$((N+1))
  cli="$(cli_of "$svc")"; nm="$(name_of "$svc")"
  echo "─────────────────────────────────────────────────────────"
  printf '%s[%d/%d] %s%s — %s\n\n' "$C_B" "$N" "$TOTAL" "$nm" "$C_0" "$(why_of "$svc")"

  # 이미 연결돼 있으면 건너뛴다
  if have "$cli"; then
    acct="$(status_of "$svc")"
    if [ -n "$acct" ]; then
      ok "이미 연결돼 있습니다 — $acct"
      DONE="$DONE $nm"
      echo
      continue
    fi
  fi

  if ! confirm "$nm 을(를) 쓰시나요?"; then
    dim "건너뜁니다."
    SKIPPED="$SKIPPED $nm"
    echo
    continue
  fi

  # 1) 프로그램 설치
  if ! have "$cli"; then
    echo
    info "먼저 $nm 프로그램을 설치해야 합니다."
    echo
    printf '      %s\n' "$(install_hint "$cli")"
    echo
    if confirm "지금 설치할까요?"; then
      info "설치 중입니다. 몇 분 걸릴 수 있습니다..."
      if eval "$(install_hint "$cli")"; then ok "설치했습니다."
      else bad "설치에 실패했습니다. 위 명령을 직접 실행해 보세요."; SKIPPED="$SKIPPED $nm"; echo; continue; fi
    else
      dim "나중에 위 명령으로 설치하세요."
      SKIPPED="$SKIPPED $nm"; echo; continue
    fi
  fi

  # 2) 계정 안내
  echo
  info "계정이 아직 없으시면 먼저 만드셔야 합니다."
  dim "  가입 주소: $(signup_url "$svc")"
  if confirm "가입 페이지를 열어드릴까요?"; then
    open_url "$(signup_url "$svc")" && ok "브라우저를 열었습니다." || bad "브라우저를 못 열었습니다. 위 주소를 직접 입력하세요."
    pause >/dev/null || true
  fi

  # 3) 로그인 안내 + 실행
  echo
  printf '  %s이제 로그인합니다.%s\n\n' "$C_B" "$C_0"
  guide_of "$svc"
  echo
  info "아래 명령을 실행합니다. 화면 안내를 따라가세요."
  printf '      %s%s%s\n\n' "$C_B" "$(login_cmd "$svc")" "$C_0"

  if confirm "지금 실행할까요?"; then
    eval "$(login_cmd "$svc")" </dev/tty || true
  else
    dim "나중에 위 명령을 직접 실행하세요."
    SKIPPED="$SKIPPED $nm"; echo; continue
  fi

  # 4) 검증
  echo
  info "정말 연결됐는지 확인합니다..."
  acct="$(status_of "$svc")"
  if [ -n "$acct" ]; then
    ok "$nm 연결 완료 — $acct"
    DONE="$DONE $nm"
  else
    bad "아직 연결되지 않았습니다."
    dim "  다시 하시려면:  $(login_cmd "$svc")"
    dim "  로그인 창을 닫으셨거나, 브라우저에서 승인을 안 누르신 경우가 많습니다."
    SKIPPED="$SKIPPED $nm"
  fi
  echo
done

echo "═════════════════════════════════════════════════════════"
echo "${C_B}정리${C_0}"
echo
[ -n "$DONE" ]    && ok "연결됨:$DONE"
[ -n "$SKIPPED" ] && dim "남음:$SKIPPED"
echo
dim "언제든 다시 확인:  connect.sh check"
dim "프로젝트별 .env 값은 각 프로젝트 안내를 따르세요. 이 도구는 계정 연결까지만 돕습니다."
