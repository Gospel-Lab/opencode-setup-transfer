# 보안 정책 / Security Policy

이 도구는 개발 환경 설정을 다루므로, API 키와 계정 자격증명 가까이에서 동작합니다.
무엇을 하고 무엇을 하지 않는지 명확히 밝힙니다.

*This tool operates near API keys and account credentials. This document states exactly what it does and does not do.*

---

## 절대 담지 않는 것 / Never packed

아카이브에 다음이 들어가는 경로는 **옵션으로도 열리지 않습니다.**

| 대상 | 이유 |
|---|---|
| `~/.local/share/opencode/auth.json` | AI 제공자 API 키 |
| `~/.local/share/opencode/opencode.db` | 전체 대화 기록 |
| `~/.local/share/opencode/log/` | 로그 (프롬프트 내용이 남을 수 있음) |
| `~/.config/gh/`, `~/.config/configstore/firebase-tools.json` | 서비스 자격증명 |
| `~/.ssh/`, `~/.aws/`, `.env` 류 | 이 도구의 수집 대상이 아님 |

`~/.config/opencode/opencode.json` 안의 제공자 키와 MCP 인증 헤더는
`<<<REDACTED:…>>>` 자리표시자로 치환됩니다. 값은 담기지 않되, **어디를 채워야 하는지는 남습니다.**

## 두 겹 스캔 / Two-layer scan

압축 직전에 페이로드 전체를 검사합니다.

1. **키 형태 탐지** — `sk-…`, `sk-or-v1-…`, `ghp_…`, `github_pat_…`, `xox[abp]-…`, `AIza…`, PEM 개인키 블록, `api_key: "…"` 형태의 대입문
2. **본인 식별자 탐지** — 실행 시점에 `whoami`, `hostname`, `git config user.email/user.name` 으로 알아낸 값

배포 모드(`--mode share`)에서 실제 설정 파일에 위 항목이 발견되면 **아카이브를 만들지 않고 중단**합니다.
테스트 픽스처나 문서 속 예시(`user@example.com`)는 경고만 하고 막지 않습니다.

개인 이전 모드(`--mode personal`)에서는 경고 후 진행합니다. 그 아카이브는 본인 것이며,
**제3자에게 전달하도록 설계되지 않았습니다.**

## 자격증명을 옮기지 않는 이유 / Why credentials are not transferred

기술적 한계가 아니라 의도한 설계입니다.

- `gh` 는 토큰을 OS 키체인에 저장합니다 — 복사할 파일이 존재하지 않습니다.
- `firebase-tools.json` 은 평문 refresh token 입니다 — 유출 시 계정 탈취로 이어집니다.
- 토큰은 기기·계정에 묶여 있어 복사해도 다른 환경에서 동작하지 않는 경우가 많습니다.

대신 **어떤 서비스에 어떤 계정으로 연결돼 있었는지만** 기록하고, 새 환경에서는 재로그인을 안내합니다.

## 로그인 자동화를 하지 않는 이유 / No credential automation

`connect.sh` 는 브라우저를 열고 무엇을 눌러야 하는지 안내하지만,
**아이디·비밀번호·2단계 인증 코드를 입력하거나 저장하지 않습니다.**

자동화하면 자격증명이 스크립트를 거쳐 가고, 로그인 화면이 바뀔 때마다 조용히 깨집니다.
안내는 깨져도 사람이 알아차리지만, 자동 입력은 깨진 채로 위험해집니다.

## 임시 파일 / Temporary files

작업은 `mktemp -d` 로 만든 디렉터리에서 이루어지고 종료 시 삭제됩니다.
비밀정보 스캔 결과에는 탐지된 문자열 일부가 포함되므로 **아카이브 바깥에** 기록되며,
성공 시 함께 삭제됩니다. 중단된 경우에는 사용자가 확인할 수 있도록 경로를 출력하고 남겨 둡니다.

## 설치 스크립트 / Install script

`curl … | bash` 는 편하지만 원격 코드를 즉시 실행합니다. 검토 후 실행하고 싶다면:

```bash
curl -fsSL https://raw.githubusercontent.com/Gospel-Lab/opencode-setup-transfer/main/install.sh -o install.sh
less install.sh          # 내용 확인
bash install.sh
```

저장소를 직접 clone 해 `skills/opencode-setup-transfer/` 폴더를
`~/.config/opencode/skills/` 로 복사해도 동일합니다.

## 취약점 제보 / Reporting a vulnerability

키 유출 경로처럼 공개하기 곤란한 문제는 공개 이슈 대신
[GitHub Security Advisory](https://github.com/Gospel-Lab/opencode-setup-transfer/security/advisories/new) 로 알려주세요.

그 외 버그는 일반 이슈로 올려주시면 됩니다.

*For issues that should not be disclosed publicly, please use the GitHub Security Advisory link above rather than a public issue.*
