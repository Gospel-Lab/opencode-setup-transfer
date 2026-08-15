# opencode 세팅 이사

*[English](README.en.md)*

지금 쓰는 컴퓨터의 opencode 세팅을 **파일 하나로 포장해서**, 새 컴퓨터에서 **자동으로 풀어놓는** 도구입니다.

노트북을 바꿨을 때, 집과 사무실 컴퓨터를 함께 쓸 때, 그동안 만든 스킬과 설정을 처음부터 다시 만들지 않아도 됩니다.

```
[옛 컴퓨터]  export.sh  →  opencode-setup-personal-….tar.gz  →  [새 컴퓨터]  import.sh
```

---

## 설치

두 컴퓨터 모두에서 한 줄이면 됩니다.

```bash
curl -fsSL https://raw.githubusercontent.com/Gospel-Lab/opencode-setup-transfer/main/install.sh | bash
```

`~/.config/opencode/skills/opencode-setup-transfer/` 에 설치됩니다.
새 컴퓨터에서는 설치 없이 아카이브 안의 `import.sh` 를 바로 실행해도 됩니다 — 도구가 아카이브에 함께 들어 있습니다.

## 쓰는 법

### 1. 옛 컴퓨터에서 내보내기

```bash
~/.config/opencode/skills/opencode-setup-transfer/scripts/export.sh
```

바탕화면에 `opencode-setup-personal-<날짜>.tar.gz` 가 생깁니다. 보통 1~5MB라 메일로도 보낼 수 있습니다.

### 2. 새 컴퓨터에서 가져오기

파일을 새 컴퓨터의 다운로드 폴더에 옮긴 뒤:

```bash
cd ~/Downloads
tar -xzf opencode-setup-personal-*.tar.gz
cd opencode-setup && ./import.sh
```

**묻지 않고 전부 적용합니다.** 기존 파일이 있으면 백업한 뒤 덮어씁니다.
항목마다 확인하고 싶으면 `./import.sh --ask`.

### 3. 서비스 다시 로그인 — 연결 도우미

터미널이 낯설어도 괜찮습니다. 마법사가 **한 서비스씩 손을 잡고** 갑니다.

```bash
~/.config/opencode/skills/opencode-setup-transfer/scripts/connect.sh wizard
```

**GitHub · Firebase · Vercel · Supabase · Netlify** 다섯 곳을 지원합니다. 각 서비스마다:

1. 프로그램이 없으면 **설치 명령을 알려주고 대신 설치**합니다
2. 계정이 없으면 **가입 페이지를 브라우저로 열어**줍니다
3. 로그인할 때 **화면에 무엇이 뜨고 어디를 눌러야 하는지** 그림으로 보여줍니다
4. 끝나면 **정말 연결됐는지 자동으로 확인**하고, 안 됐으면 원인을 짚어줍니다
5. 이미 연결된 서비스는 **건너뜁니다**. 안 쓰는 서비스도 건너뛸 수 있습니다

상태만 빠르게 보려면:

```bash
connect.sh check
```

```
서비스 연결 상태

  GitHub     연결됨  my-github-id
  Firebase   연결됨  me@example.com
  Vercel     로그인 필요   vercel login
  Supabase   설치 안 됨    brew install supabase/tap/supabase
  Netlify    연결됨  me@example.com
```

특정 서비스만 하고 싶으면 이름을 붙이세요 — `connect.sh wizard firebase`

> 로그인을 **대신 해 주지는 않습니다.** 비밀번호와 2단계 인증은 본인만 다뤄야 하고,
> 로그인 화면은 수시로 바뀌어 자동화하면 곧 깨집니다. 대신 길을 끝까지 안내합니다.

---

## 무엇이 옮겨지나

| 항목 | 이사 방식 |
|---|---|
| 스킬·명령·에이전트·테마·플러그인 | 파일로 그대로 |
| `opencode.json` | 옮기되 키 값은 자리표시자로 비움 |
| 전역 `AGENTS.md` | 파일로 그대로 |
| `~/.claude/skills/` | 함께 옮김 (opencode 가 자동 인식하는 위치) |
| AI 제공자 키 | **안 옮김** — 새 컴퓨터에서 `opencode auth login` |
| GitHub·Firebase·Vercel | **안 옮김** — 다시 로그인 (목록은 알려줌) |
| 대화 기록·로그·`node_modules` | 안 옮김 |

### 왜 로그인 정보는 안 옮기나

자격증명은 파일이 아니라 **계정에 묶여** 있습니다.

- `gh` 는 토큰을 OS 키체인에 넣습니다 — 복사할 파일이 애초에 없습니다.
- `firebase-tools.json` 은 평문 refresh token 이라, 남에게 넘어가면 계정 탈취입니다.
- Vercel 은 저장소별 `.env.production.local` 의 토큰을 씁니다 — 저장소와 함께 움직입니다.

그래서 이 도구는 **"무엇에 어떤 계정으로 연결돼 있었는지"만** 기록하고, 새 컴퓨터에서는 설치·로그인 상태를 점검해 **아직 안 된 것의 명령만** 알려줍니다.

---

## 남에게 나눠줄 때

```bash
export.sh --mode share
```

전역 지침과 계정 정보를 빼고 만듭니다. 비밀값이나 본인 식별정보(계정명·이메일·호스트명)가 발견되면 **파일을 아예 만들지 않습니다.** 특정 파일이 걸리면 빼고 다시 실행하세요.

```bash
export.sh --mode share --exclude my-private-script.sh
```

---

## 옵션

**export.sh**

| 옵션 | 설명 |
|---|---|
| *(없음)* | 내 이사용 (기본) |
| `--mode share` | 배포용 — 개인정보 제외, 발견 시 중단 |
| `--out <경로>` | 저장 위치 지정 |
| `--exclude <이름>` | 특정 파일·폴더 제외 |
| `--config-dir <경로>` | 설정 폴더 직접 지정 |
| `--force` | 경고 무시하고 강행 |

**import.sh**

| 옵션 | 설명 |
|---|---|
| *(없음)* | 확인 없이 전부 적용 (기본) |
| `--ask` | 항목마다 확인 |
| `--from <파일>` | tar.gz 를 바로 지정 |

**connect.sh**

| 명령 | 설명 |
|---|---|
| `wizard [서비스]` | 안내를 받으며 연결. 서비스 이름을 주면 그것만 |
| `check` | 현재 연결 상태 |

**connections.sh**

| 명령 | 설명 |
|---|---|
| `setup` | 이 컴퓨터에 필요한 로그인 안내 |
| `report` | 현재 연결 상태를 문서로 |

---

## 안전장치

- **화이트리스트 방식** — 목록에 있는 것만 담습니다. 모르는 파일이 딸려가지 않습니다.
- **`~/.local/share/opencode/` 는 어떤 옵션으로도 담기지 않습니다** — API 키와 대화 기록이 있는 곳입니다.
- **두 겹 스캔** — API 키 형태와, 실행 시점에 알아낸 본인 식별자를 함께 검사합니다.
- **경로 템플릿화** — 파일 속 홈 경로를 `{{HOME}}` 로 바꿔 담고 복원합니다. 사용자 이름이 달라도 동작합니다.
- **가져오기 전 백업** — `~/.config/opencode/backups/import-<시각>/` 에 남깁니다.
- **심볼릭 링크 실체화** — opencode 는 링크된 스킬 폴더를 따라가지 않으므로 내용을 복사합니다. 5MB 초과 도구는 제외하고 `SYMLINKS.md` 에 기록합니다.
- **외부 CLI 호출에 제한 시간** — 로그인 대기로 스크립트가 멈추지 않게 합니다.

자세한 내용은 [SECURITY.md](SECURITY.md) 를 보세요.

## 요구사항

- macOS, Linux, 또는 WSL (Windows 는 WSL 권장 — opencode 공식 권장 방식입니다)
- `bash`, `tar`, `rsync`, `python3` (대부분 기본 설치돼 있습니다)
- [opencode](https://opencode.ai)

## 라이선스

MIT
