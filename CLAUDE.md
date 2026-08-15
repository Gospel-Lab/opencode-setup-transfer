# AI 에이전트를 위한 설치 지시문

이 파일은 **AI 코딩 도구(opencode·Claude Code·codex)가 읽는 지시문**입니다.
사용자가 이 저장소 주소를 주며 "설치해줘"라고 하면, 아래를 그대로 따르세요.

*This file instructs AI coding agents. If a user asks you to install this repository, follow these steps exactly.*

---

## 사용자가 원하는 것

이 저장소는 **AI 도구 세팅을 다른 컴퓨터로 옮기는 도구**입니다. 사용자는 보통 둘 중 하나를 원합니다.

1. **설치** — 이 도구를 자기 컴퓨터에 깔기
2. **내보내기** — 지금 세팅을 파일 하나로 포장하기 (설치가 끝난 뒤)

무엇을 원하는지 불분명하면 물어보세요. 대부분은 1번입니다.

## 설치 절차

### 1단계 — 설치 위치 정하기

스킬은 opencode 설정 폴더 안 `skills/ai-setup-transfer/` 에 둡니다.

```bash
# 이 명령이 알려주는 config 경로를 쓰세요
opencode debug paths
```

명령이 없거나 실패하면 표준 경로를 씁니다.

| 운영체제 | 경로 |
|---|---|
| macOS · Linux | `~/.config/opencode/skills/ai-setup-transfer/` |
| Windows | `%USERPROFILE%\.config\opencode\skills\ai-setup-transfer\` |

`OPENCODE_CONFIG_DIR` 환경변수가 다른 곳을 가리키더라도 **`opencode debug paths` 결과를 우선**하세요. 일부 실행 환경이 이 변수를 덮어씁니다.

### 2단계 — 내려받아 복사하기

**맥 · 리눅스 · WSL:**

```bash
curl -fsSL https://raw.githubusercontent.com/Gospel-Lab/ai-setup-transfer/main/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/Gospel-Lab/ai-setup-transfer/main/install.ps1 | iex
```

설치 스크립트를 쓸 수 없는 상황이면 직접 하세요.

```bash
git clone --depth 1 https://github.com/Gospel-Lab/ai-setup-transfer.git /tmp/ai-setup-transfer
mkdir -p "$(opencode debug paths | awk '$1=="config"{print $2}')/skills"
cp -R /tmp/ai-setup-transfer/skills/ai-setup-transfer "<config>/skills/"
chmod +x "<config>/skills/ai-setup-transfer/scripts/"*.sh
rm -rf /tmp/ai-setup-transfer
```

### 3단계 — 확인하고 알려주기

설치가 끝나면 사용자에게 **다음에 무엇을 할지** 알려주세요.

```
설치했습니다. 이제 이렇게 쓰시면 됩니다:

  내 세팅 내보내기 (지금 쓰는 컴퓨터에서)
    맥·리눅스:  ~/.config/opencode/skills/ai-setup-transfer/scripts/export.sh
    윈도우:     powershell -File "%USERPROFILE%\.config\opencode\skills\ai-setup-transfer\scripts\export.ps1"

  서비스 연결 도우미
    맥·리눅스:  .../scripts/connect.sh wizard
    윈도우:     powershell -File "...\scripts\connect.ps1" -Mode wizard
```

opencode 를 **껐다 켜야** 새 스킬이 인식됩니다. 이 점을 반드시 알려주세요.

---

## 하지 말아야 할 것

- **사용자의 기존 설정을 지우거나 덮어쓰지 마세요.** 이 도구는 스킬 폴더만 추가합니다.
- **`~/.local/share/opencode/`, `~/.codex/auth.json`, `~/.claude/projects/` 를 열거나 옮기지 마세요.** API 키와 대화 기록이 있는 곳입니다.
- **사용자 대신 로그인하지 마세요.** 서비스 연결은 `connect.sh`/`connect.ps1` 마법사가 안내하고, 실제 입력은 사용자가 합니다.
- **아카이브 파일을 사용자 동의 없이 어디에도 올리지 마세요.** 개인 세팅이 들어 있습니다.

## 이 저장소의 구조

```
install.sh / install.ps1              한 줄 설치
skills/ai-setup-transfer/
  SKILL.md                            도구 설명 (AI 가 읽는 스킬 정의)
  scripts/
    export.sh  / export.ps1           내보내기
    import.sh  / import.ps1           가져오기 (아카이브에 함께 담김)
    connect.sh / connect.ps1          서비스 연결 마법사
    connections.sh                    연결 상태 기록
```

`.sh` 는 맥·리눅스·WSL, `.ps1` 은 윈도우용입니다. **같은 기능이므로 한쪽만 고치면 안 됩니다.**

## 더 읽을 것

- [README.md](README.md) — 사람이 읽는 사용법
- [SECURITY.md](SECURITY.md) — 무엇을 담지 않는지, 왜 자격증명을 옮기지 않는지
