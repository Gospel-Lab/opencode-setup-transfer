---
name: opencode-setup-transfer
description: Use when moving AI coding tool setups (opencode, Claude Code, codex — configs, agents, commands, skills, themes, plugins, global instructions) and connected services (GitHub/Firebase/Vercel/Supabase/Netlify) from one computer to another, backing them up, or packaging them for others. Triggers — "opencode 세팅 옮기기", "다른 컴퓨터에 세팅 이사", "새 노트북에 그대로 설치", "수강생에게 세팅 배포", "깃허브·파이어베이스·버셀 연결도 같이", "export/import opencode config".
---

# AI 도구 세팅 이사

**이 컴퓨터에 깔려 있는 AI 도구를 실행 시점에 찾아** 각각의 설정을 담습니다. opencode · Claude Code · codex 를 지원하고, 없는 도구는 건너뜁니다.

설정 폴더를 통째로 복사하면 대화 기록·로그·캐시가 따라오고 API 키까지 넘어갑니다(codex 의 `sessions` 만 1GB가 넘습니다). 이 스킬은 목록에 있는 것만 골라 담고, 비밀값을 자리표시자로 바꾸고, 절대경로를 템플릿화한 뒤 반대편에서 **병합**합니다.

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

| 도구 | 설정 폴더 | 담는 것 |
|---|---|---|
| opencode | `~/.config/opencode` | `opencode.json`·`.jsonc`, `agent(s)`·`command(s)`·`skill(s)`·`theme(s)`·`mode(s)`·`plugin(s)`, `package.json`, (personal) `AGENTS.md` |
| Claude Code | `~/.claude` | `settings.json`, `skills`·`commands`·`hooks`·`scripts`, `statusline.sh`, 플러그인 목록, (personal) `CLAUDE.md` |
| codex | `~/.codex` | `config.toml`, `skills`, `prompts`, (personal) `AGENTS.md` |

경로는 환경변수(`CLAUDE_CONFIG_DIR`, `CODEX_HOME`)와 `opencode debug paths` 로 **실행할 때마다 확인**합니다.

**제외**: 각 도구의 인증 파일, 대화 기록·세션·로그·캐시, `node_modules`·플러그인 캐시, 서비스 토큰

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

`~/.ssh`, 프로젝트별 환경변수(`.env`), 각 서비스의 프로젝트 설정. 이 도구는 opencode 설정과 계정 연결까지만 다룹니다.
