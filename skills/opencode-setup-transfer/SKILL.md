---
name: opencode-setup-transfer
description: Use when moving an opencode setup (opencode.json, agents, commands, skills, themes, plugins, global AGENTS.md, and connected services like GitHub/Firebase/Vercel) from one computer to another, backing it up, or packaging it for students. Triggers — "opencode 세팅 옮기기", "다른 컴퓨터에 세팅 이사", "새 노트북에 그대로 설치", "수강생에게 세팅 배포", "깃허브·파이어베이스·버셀 연결도 같이", "export/import opencode config".
---

# opencode 세팅 이사

`~/.config/opencode` 를 통째로 복사하면 60MB짜리 `node_modules`가 따라오고, `~/.local/share/opencode`까지 복사하면 **API 키와 전체 대화 기록**이 함께 넘어갑니다. 이 스킬은 필요한 것만 골라 담고, 비밀값을 자리표시자로 바꾸고, 절대경로를 템플릿화한 아카이브를 만든 뒤 반대편에서 **병합**합니다.

## 두 가지 모드

| 모드 | 용도 | 포함 |
|---|---|---|
| `personal` | 내 다른 컴퓨터로 이전·백업 | 아래 전부 + 전역 `AGENTS.md` + 연결 계정 실명 |
| `share` | 수강생·팀원에게 배포 | 설정·스킬·명령·플러그인 목록만, 계정은 가림 |

`personal` 이 기본값입니다. `share` 모드는 비밀값이나 **본인 식별정보(계정명·이메일·호스트명)** 가 실제 설정 파일에서 발견되면 중단합니다. `--exclude <파일명>` 으로 빼고 다시 실행하세요.

## 절차

### 1) 내보내기 (원본 컴퓨터)

```bash
# 기본이 personal 이라 옵션 없이 실행하면 내 이사용 아카이브가 만들어진다
~/.config/opencode/skills/opencode-setup-transfer/scripts/export.sh
# 남에게 줄 때만
~/.config/opencode/skills/opencode-setup-transfer/scripts/export.sh --mode share
```

결과: `~/Desktop/opencode-setup-<모드>-<날짜>.tar.gz` (import.sh·connections.sh 동봉)

### 2) 가져오기 (새 컴퓨터)

```bash
tar -xzf opencode-setup-personal-YYYYMMDD.tar.gz
cd opencode-setup && ./import.sh
```

항목마다 y/N을 묻고, 기존 파일은 기본적으로 덮어쓰지 않습니다. 가져오기 전 상태는 `~/.config/opencode/backups/import-<시각>/` 에 백업됩니다. 마지막에 `opencode debug config` 로 설정이 실제로 읽히는지 검증하고, 연결 점검 결과와 남은 작업을 출력합니다.

## 포함 / 제외

**포함**: `opencode.json`(비밀값 치환), `agent(s)/`·`command(s)/`·`skill(s)/`·`theme(s)/`·`mode(s)/`·`plugin(s)/`, `package.json`, 플러그인 재설치 명령, 연결 서비스 목록, (personal) 전역 `AGENTS.md`

**함께 담는 것 — `~/.claude/skills/`**: opencode는 이 폴더를 외부 스킬로 자동 인식합니다. 강의 스킬 자산의 본체이므로 `external-claude-skills/` 로 담아 그대로 복원합니다.

**제외**: `~/.local/share/opencode/` 전체(`auth.json` = API 키, `opencode.db` = 대화 기록, 로그), `node_modules`(약 60MB), GitHub·Firebase·Vercel 토큰

## 연결 서비스는 복사하지 않고 다시 로그인시킨다

이게 이 스킬의 핵심 판단입니다. **자격증명은 파일이 아니라 계정에 묶여 있습니다.**

- `gh` 는 토큰을 OS 키체인에 넣습니다 — 복사할 파일이 애초에 없습니다.
- `firebase-tools.json` 은 평문 refresh token 입니다 — 남에게 넘어가면 계정 탈취입니다.
- Vercel 은 레포별 `.env.production.local` 의 `VERCEL_TOKEN` 을 씁니다 — 레포와 함께 움직입니다.

그래서 `connections.sh` 가 **"무엇에 어떤 계정으로 연결돼 있었는지"만** 기록하고(share 모드에서는 가림), 새 컴퓨터에서는 설치 여부와 로그인 상태를 점검해 필요한 로그인 명령만 순서대로 출력합니다.

```bash
scripts/connections.sh report   # 현재 연결 상태를 문서로
scripts/connections.sh setup    # 이 컴퓨터에 필요한 로그인 안내
```

## 도구가 스스로 따라간다

이 스킬은 `~/.config/opencode/skills/` 안에 있고, 그 폴더는 아카이브에 함께 담깁니다.
따라서 **한 번 설치한 사람은 새 컴퓨터에서도 계속 이 도구로 이사할 수 있습니다.**
별도 설치 절차를 안내할 필요가 없습니다.

## 반드시 지킬 것

- **`~/.config/opencode` 통째 복사·rsync 를 제안하지 않는다.**
- **사용자의 personal 아카이브를 제3자에게 전달하지 않는다.** 수강생에게는 이 스킬이나 share 아카이브를 준다.
- **심볼릭 링크 스킬은 실체를 복사한다.** opencode 는 링크된 스킬 폴더를 따라가지 않아, 링크째 옮기면 새 컴퓨터에서 인식되지 않는다. 5MB 넘는 대형 도구는 제외하고 별도 설치를 안내한다.
- 설정 변경 후에는 **opencode 재시작**이 필요하다고 알린다. 설정은 시작할 때 한 번만 읽힌다.
- 프로젝트별 `.env`·`.firebaserc`·`.vercel/project.json` 은 저장소에 속하므로 다루지 않는다.
- **설정 폴더는 `opencode debug paths` 로 확인한다.** 일부 실행 환경이 `OPENCODE_CONFIG_DIR` 을 다른 곳으로 덮어써서, 환경변수를 그대로 믿으면 엉뚱한 폴더를 내보낸다.
- 외부 CLI(`gh`·`firebase`·`vercel`) 호출에는 반드시 제한 시간을 건다. 로그인 대기로 멈춘다.

## 이 스킬의 범위 밖

`~/.hermes`, Obsidian vault, VPS 상태, `~/.ssh`, 프로젝트별 환경변수. Claude Code 설정 이전은 `~/.claude/skills/claude-setup-transfer` 가 따로 있습니다.
