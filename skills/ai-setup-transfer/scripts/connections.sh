#!/usr/bin/env bash
# 개발 서비스 연결 상태 점검 — GitHub·Firebase·Vercel 등
#
# 핵심 전제: 자격증명(토큰)은 파일로 옮기지 않는다.
#   - gh 는 토큰을 OS 키체인에 넣으므로 복사할 파일 자체가 없다
#   - firebase-tools.json 은 평문 refresh token 이라 남에게 넘어가면 계정 탈취다
#   - vercel 은 이 계정에서 레포별 .env.production.local 토큰을 쓴다
# 그래서 "무엇에 어떤 계정으로 연결돼 있었는지"만 기록하고, 새 컴퓨터에서는 재로그인한다.
set -uo pipefail

MODE="${1:-report}"      # report | setup
SHOW_ACCOUNT="${2:-full}" # full | masked

mask() { # 이메일·계정명을 가린다 (배포용 산출물에서 사용)
  printf '%s' "$1" | sed -E 's/^(.{2}).*(@.*)$/\1***\2/; s/^([A-Za-z0-9]{2})[A-Za-z0-9_-]+$/\1***/'
}
show() { [ "$SHOW_ACCOUNT" = "masked" ] && mask "$1" || printf '%s' "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

# 로그인이 안 된 상태에서 CLI 를 부르면 브라우저 로그인 창을 띄우거나 입력을 기다리며 멈춘다.
# 그래서 먼저 "인증 파일이 있는가"만 파일로 확인하고, 있을 때만 CLI 에게 계정명을 묻는다.
# 모든 호출은 stdin 을 끊어(</dev/null) 어떤 경우에도 사용자 입력을 기다리지 못하게 한다.
authed() { # 서비스 → 인증 흔적이 있으면 0
  case "$1" in
    vercel)
      [ -s "$HOME/Library/Application Support/com.vercel.cli/auth.json" ] || \
      [ -s "$HOME/.local/share/com.vercel.cli/auth.json" ] || \
      [ -n "${VERCEL_TOKEN:-}" ] ;;
    netlify)
      [ -s "$HOME/Library/Preferences/netlify/config.json" ] || \
      [ -s "$HOME/.config/netlify/config.json" ] || \
      [ -n "${NETLIFY_AUTH_TOKEN:-}" ] ;;
    firebase)
      [ -s "$HOME/.config/configstore/firebase-tools.json" ] || \
      [ -n "${FIREBASE_TOKEN:-}" ] ;;
    supabase)
      [ -s "$HOME/.supabase/access-token" ] || \
      [ -s "$HOME/Library/Application Support/supabase/access-token" ] || \
      [ -n "${SUPABASE_ACCESS_TOKEN:-}" ] ;;
    github) return 0 ;;   # gh auth status 는 로그인 창을 띄우지 않는다
    *) return 1 ;;
  esac
}


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


# ---------------------------------------------------------------- report
if [ "$MODE" = "report" ]; then
  echo "# 연결된 서비스"
  echo
  echo "새 컴퓨터에서는 아래 서비스에 **본인 계정으로 다시 로그인**해야 합니다."
  echo "토큰은 이 파일에 담기지 않습니다."
  echo

  # --- GitHub
  if have gh; then
    accounts="$(tmo 8 gh auth status </dev/null 2>&1 | grep -oE 'account [A-Za-z0-9_-]+' | awk '{print $2}' | sort -u)"
    if [ -n "$accounts" ]; then
      echo "## GitHub (gh CLI)"
      while IFS= read -r a; do
        [ -n "$a" ] && echo "- 계정 \`$(show "$a")\` 로 로그인돼 있었습니다"
      done <<< "$accounts"
      n=$(printf '%s\n' "$accounts" | grep -c .)
      [ "$n" -gt 1 ] && echo "- ⚠️ 계정이 ${n}개입니다. 새 컴퓨터에서도 각각 로그인한 뒤, 레포마다 활성 계정을 맞춰야 push 가 됩니다."
      echo
    fi
  fi

  # --- Firebase
  if have firebase; then
    fb="$(authed firebase && tmo 12 firebase login:list </dev/null 2>/dev/null | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | head -1)"
    if [ -n "$fb" ]; then
      echo "## Firebase"
      echo "- 계정 \`$(show "$fb")\` 로 로그인돼 있었습니다"
      echo
    fi
  fi

  # --- Vercel
  if have vercel || have npx; then
    vc="$(authed vercel && tmo 12 vercel whoami </dev/null 2>/dev/null | tail -1 | tr -d '[:space:]')"
    echo "## Vercel"
    if [ -n "$vc" ] && [ "${#vc}" -lt 40 ]; then
      echo "- 계정 \`$(show "$vc")\` 로 로그인돼 있었습니다"
    else
      echo "- 전역 로그인은 없었습니다. 프로젝트별 토큰(\`.env.production.local\` 의 \`VERCEL_TOKEN\`)을 쓰는 방식입니다."
    fi
    echo
  fi

  # --- AI 제공자 (opencode)
  AUTH="$HOME/.local/share/opencode/auth.json"
  if [ -f "$AUTH" ]; then
    provs="$(python3 -c "import json;print(' '.join(json.load(open('$AUTH')).keys()))" 2>/dev/null)"
    if [ -n "$provs" ]; then
      echo "## AI 제공자 (opencode)"
      for p in $provs; do echo "- \`$p\` 에 연결돼 있었습니다 — 새 컴퓨터에서는 **본인 API 키**가 필요합니다"; done
      echo
    fi
  fi

  echo "## 프로젝트별 설정은 옮기지 않습니다"
  echo
  echo "\`.env\`, \`.env.local\`, \`.firebaserc\`, \`.vercel/project.json\` 같은 파일은 각 프로젝트 저장소에 속합니다."
  echo "새 컴퓨터에서 저장소를 clone 한 뒤, 프로젝트별 안내에 따라 다시 채우세요."
  exit 0
fi

# ---------------------------------------------------------------- setup
if [ "$MODE" = "setup" ]; then
  echo "== 서비스 연결 점검"
  echo

  # 한글은 폭이 2칸이라 printf 정렬이 어긋난다. 표 대신 목록으로 낸다.
  status() { # 서비스 설치여부 상태
    printf '  %-9s · %s · %s\n' "$1" "$2" "$3"
  }

  TODO=""

  if have gh; then
    if tmo 8 gh auth status </dev/null >/dev/null 2>&1; then
      acct="$(tmo 8 gh auth status </dev/null 2>&1 | grep -oE 'account [A-Za-z0-9_-]+' | awk '{print $2}' | paste -sd, -)"
      status "GitHub" "설치됨" "로그인됨 ($acct)"
    else
      status "GitHub" "설치됨" "로그인 필요"
      TODO="$TODO
gh auth login                      # GitHub 로그인 (브라우저)"
    fi
  else
    status "GitHub" "없음" "gh 설치 필요"
    TODO="$TODO
brew install gh                    # 맥 / 윈도우는 winget install GitHub.cli
gh auth login"
  fi

  if have firebase; then
    fb="$(authed firebase && tmo 12 firebase login:list </dev/null 2>/dev/null | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | head -1)"
    if [ -n "$fb" ]; then status "Firebase" "설치됨" "로그인됨 ($fb)"
    else
      status "Firebase" "설치됨" "로그인 필요"
      TODO="$TODO
firebase login                     # Firebase 로그인 (브라우저)"
    fi
  else
    status "Firebase" "없음" "쓰는 경우에만 설치"
  fi

  if have vercel; then
    vc="$(authed vercel && tmo 12 vercel whoami </dev/null 2>/dev/null | tail -1 | tr -d '[:space:]')"
    if [ -n "$vc" ] && [ "${#vc}" -lt 40 ]; then status "Vercel" "설치됨" "로그인됨 ($vc)"
    else
      status "Vercel" "설치됨" "로그인 필요"
      TODO="$TODO
vercel login                       # Vercel 로그인 (브라우저)"
    fi
  else
    status "Vercel" "없음" "쓰는 경우에만 설치"
  fi

  if have git; then
    gname="$(git config --global user.name 2>/dev/null)"
    gmail="$(git config --global user.email 2>/dev/null)"
    if [ -n "$gname" ] && [ -n "$gmail" ]; then status "git" "설치됨" "$gname <$gmail>"
    else
      status "git" "설치됨" "이름·이메일 미설정"
      TODO="$TODO
git config --global user.name  \"내 이름\"
git config --global user.email \"내 이메일\""
    fi
  else
    status "git" "없음" "설치 필요"
  fi

  AUTH="$HOME/.local/share/opencode/auth.json"
  if [ -f "$AUTH" ] && [ -s "$AUTH" ]; then
    provs="$(python3 -c "import json;print(','.join(json.load(open('$AUTH')).keys()))" 2>/dev/null)"
    status "opencode" "설치됨" "제공자 연결됨 ($provs)"
  else
    status "opencode" "-" "AI 제공자 연결 필요"
    TODO="$TODO
opencode auth login                # AI 제공자 연결 (본인 API 키 필요)"
  fi

  echo
  if [ -n "$TODO" ]; then
    echo "== 아직 해야 할 것"
    echo "$TODO"
    echo
    echo "  ※ 계정이 여러 개인 서비스는 어느 계정으로 로그인하는지 꼭 확인하세요."
  else
    echo "== 모든 서비스가 연결돼 있습니다."
  fi
  exit 0
fi

echo "사용법: connections.sh [report|setup] [full|masked]" >&2
exit 1
