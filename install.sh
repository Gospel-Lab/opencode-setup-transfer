#!/usr/bin/env bash
# AI 도구 세팅 이사 설치
#
#   curl -fsSL https://raw.githubusercontent.com/Gospel-Lab/ai-setup-transfer/main/install.sh | bash
#
# 하는 일: 이 저장소의 스킬을 설정 폴더에 넣고 실행 권한을 준다.
set -euo pipefail

REPO="${REPO:-Gospel-Lab/ai-setup-transfer}"
BRANCH="${BRANCH:-main}"
NAME="ai-setup-transfer"

# 설정 폴더는 opencode 에게 묻는다. 없으면 표준 경로를 쓴다.
CONF=""
if command -v opencode >/dev/null 2>&1; then
  CONF="$(opencode debug paths 2>/dev/null | awk '$1=="config"{ $1=""; sub(/^ +/,""); print; exit }')"
fi
CONF="${CONF:-$HOME/.config/opencode}"
DEST="$CONF/skills/$NAME"

echo "AI 도구 세팅 이사를 설치합니다."
echo "  설치 위치: $DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "  내려받는 중..."
if command -v git >/dev/null 2>&1; then
  git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$TMP/repo" >/dev/null 2>&1 \
    || { echo "오류: 저장소를 내려받지 못했습니다. 인터넷 연결과 주소를 확인하세요." >&2; exit 1; }
  SRC="$TMP/repo/skills/$NAME"
else
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" -o "$TMP/src.tar.gz" \
    || { echo "오류: 내려받기에 실패했습니다." >&2; exit 1; }
  tar -xzf "$TMP/src.tar.gz" -C "$TMP"
  SRC="$(find "$TMP" -type d -path "*/skills/$NAME" | head -1)"
fi

[ -d "$SRC" ] || { echo "오류: 저장소 안에서 스킬 폴더를 찾지 못했습니다." >&2; exit 1; }

# 기존 설치본이 있으면 백업한다
if [ -d "$DEST" ]; then
  BK="$CONF/backups/tool-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BK"
  cp -R "$DEST" "$BK/" 2>/dev/null || true
  echo "  기존 설치본 백업: $BK"
fi

mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/
chmod +x "$DEST"/scripts/*.sh 2>/dev/null || true

echo
echo "설치 완료."
echo
echo "▸ 지금 쓰던 컴퓨터에서 — 내 세팅을 파일 하나로 포장"
echo "    $DEST/scripts/export.sh"
echo
echo "▸ 새 컴퓨터에서 — 그 파일을 풀고 실행하면 자동 적용"
echo "    tar -xzf ai-setup-personal-*.tar.gz"
echo "    cd ai-setup && ./import.sh"
echo
echo "▸ 깃허브·파이어베이스 같은 서비스 연결"
echo "    $DEST/scripts/connect.sh wizard"
