# 백엔드·배포 서비스 연결 도우미 (Windows)
#
#   powershell -ExecutionPolicy Bypass -File connect.ps1 -Mode wizard
#   powershell -ExecutionPolicy Bypass -File connect.ps1 -Mode check
#
# 로그인을 대신해 주지는 않는다. 비밀번호와 2단계 인증은 본인만 다뤄야 하고,
# 로그인 화면은 수시로 바뀌어 자동화하면 곧 깨진다. 대신 길을 끝까지 안내한다.
[CmdletBinding()]
param(
  [ValidateSet('wizard','check','report')][string]$Mode = 'wizard',
  [string]$Service = '',
  [switch]$Masked
)

$ErrorActionPreference = 'Continue'
function Say($m)  { Write-Host $m }
function OK($m)   { Write-Host "  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  $m" -ForegroundColor Yellow }
function Dim($m)  { Write-Host "  $m" -ForegroundColor DarkGray }

$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$Services = if ($Service) { @($Service) } else { @('github','firebase','vercel','supabase','netlify') }

function Have([string]$c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Mask([string]$v) {
  if (-not $v) { return $v }
  if ($v -match '^(.{2}).*(@.*)$') { return ($Matches[1] + '***' + $Matches[2]) }
  if ($v.Length -gt 2) { return ($v.Substring(0,2) + '***') }
  return '***'
}
function Show([string]$v) { if ($Masked) { Mask $v } else { $v } }

function Get-Label([string]$s) {
  switch ($s) { 'github'{'GitHub'} 'firebase'{'Firebase'} 'vercel'{'Vercel'} 'supabase'{'Supabase'} 'netlify'{'Netlify'} }
}
function Get-Cli([string]$s) {
  switch ($s) { 'github'{'gh'} 'firebase'{'firebase'} 'vercel'{'vercel'} 'supabase'{'supabase'} 'netlify'{'netlify'} }
}
function Get-Why([string]$s) {
  switch ($s) {
    'github'  {'코드를 저장하고 버전을 관리하는 곳'}
    'firebase'{'앱의 데이터베이스와 로그인 기능을 맡는 곳'}
    'vercel'  {'만든 웹사이트를 인터넷에 올리는 곳'}
    'supabase'{'데이터베이스(PostgreSQL)를 빌려 쓰는 곳'}
    'netlify' {'웹사이트를 올리는 곳 (Vercel 과 비슷한 역할)'}
  }
}
function Get-InstallCmd([string]$s) {
  # winget 은 Windows 10 1809+ 에 기본 포함돼 있다
  switch ($s) {
    'github'  {'winget install --id GitHub.cli -e'}
    'firebase'{'npm install -g firebase-tools'}
    'vercel'  {'npm install -g vercel'}
    'supabase'{'winget install --id Supabase.CLI -e'}
    'netlify' {'npm install -g netlify-cli'}
  }
}
function Get-LoginCmd([string]$s) {
  switch ($s) {
    'github'{'gh auth login'} 'firebase'{'firebase login'} 'vercel'{'vercel login'}
    'supabase'{'supabase login'} 'netlify'{'netlify login'}
  }
}
function Get-SignupUrl([string]$s) {
  switch ($s) {
    'github'{'https://github.com/signup'} 'firebase'{'https://console.firebase.google.com'}
    'vercel'{'https://vercel.com/signup'} 'supabase'{'https://supabase.com/dashboard'}
    'netlify'{'https://app.netlify.com/signup'}
  }
}

# 로그인이 안 된 상태에서 CLI 를 부르면 로그인 창을 띄우거나 입력을 기다리며 멈춘다.
# 먼저 인증 파일이 있는지 확인하고, 있을 때만 계정명을 묻는다.
function Test-Authed([string]$s) {
  # APPDATA 는 윈도우에만 있다. 없는 환경에서도 죽지 않도록 후보 경로를 모아 확인한다.
  function AnyPath([string[]]$paths) {
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p -ErrorAction SilentlyContinue)) { return $true } }
    return $false
  }
  $appdata = $env:APPDATA
  switch ($s) {
    'github'   { return $true }   # gh auth status 는 창을 띄우지 않는다
    'vercel'   { return ((AnyPath @(
                    $(if ($appdata) { Join-Path $appdata 'com.vercel.cli\auth.json' }),
                    (Join-Path $HomeDir '.local\share\com.vercel.cli\auth.json'),
                    (Join-Path $HomeDir 'Library/Application Support/com.vercel.cli/auth.json')
                  )) -or [bool]$env:VERCEL_TOKEN) }
    'netlify'  { return ((AnyPath @(
                    $(if ($appdata) { Join-Path $appdata 'netlify\Config\config.json' }),
                    (Join-Path $HomeDir '.config/netlify/config.json'),
                    (Join-Path $HomeDir 'Library/Preferences/netlify/config.json')
                  )) -or [bool]$env:NETLIFY_AUTH_TOKEN) }
    'firebase' { return ((AnyPath @(
                    $(if ($appdata) { Join-Path $appdata 'configstore\firebase-tools.json' }),
                    (Join-Path $HomeDir '.config/configstore/firebase-tools.json')
                  )) -or [bool]$env:FIREBASE_TOKEN) }
    'supabase' { return ((AnyPath @(
                    $(if ($appdata) { Join-Path $appdata 'supabase\access-token' }),
                    (Join-Path $HomeDir '.supabase/access-token')
                  )) -or [bool]$env:SUPABASE_ACCESS_TOKEN) }
  }
  return $false
}

function Invoke-WithTimeout([scriptblock]$Block, [int]$Seconds = 12) {
  $job = Start-Job -ScriptBlock $Block
  if (Wait-Job $job -Timeout $Seconds) { $r = Receive-Job $job } else { $r = $null; Stop-Job $job -ErrorAction SilentlyContinue }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  return $r
}

function Get-Account([string]$s) {
  $cli = Get-Cli $s
  if (-not (Have $cli)) { return $null }
  if (-not (Test-Authed $s)) { return $null }
  try {
    switch ($s) {
      'github' {
        $o = Invoke-WithTimeout { (& gh auth status 2>&1) -join "`n" } 10
        if ($o) { $m = [regex]::Matches($o, 'account\s+([A-Za-z0-9_\-]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
                  if ($m) { return ($m -join ',') } }
      }
      'firebase' {
        $o = Invoke-WithTimeout { (& firebase login:list 2>$null) -join "`n" } 15
        if ($o -and $o -match '([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+)') { return $Matches[1] }
      }
      'vercel' {
        $o = Invoke-WithTimeout { (& vercel whoami 2>$null) -join "`n" } 15
        if ($o) { $l = ($o -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
                  if ($l -match '^[A-Za-z0-9_\-]{1,39}$') { return $l } }
      }
      'supabase' {
        $o = Invoke-WithTimeout { (& supabase projects list 2>$null) -join "`n" } 15
        if ($o -and $o -match '\|') { return '연결됨' }
      }
      'netlify' {
        $o = Invoke-WithTimeout { (& netlify status 2>$null) -join "`n" } 15
        if ($o -and $o -match '([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+)') { return $Matches[1] }
      }
    }
  } catch { }
  return $null
}

function Show-LoginGuide([string]$s) {
  switch ($s) {
    'github' { @'
  터미널에 이런 화면이 차례로 나옵니다. 방향키로 고르고 엔터를 누르세요.

    ? What account do you want to log into?
        > GitHub.com               ← 이걸 고릅니다
    ? What is your preferred protocol?
        > HTTPS                    ← 이걸 고릅니다
    ? How would you like to authenticate?
        > Login with a web browser ← 이걸 고릅니다

  여덟 자리 코드가 나옵니다. 예: A1B2-C3D4
  코드를 복사하고 엔터를 누르면 브라우저가 열립니다.
  브라우저 칸에 코드를 붙여넣고 Continue → Authorize 를 누르세요.
'@ }
    'firebase' { @'
  브라우저에 구글 로그인 화면이 뜹니다.

    1. 앱에서 쓸 구글 계정을 고릅니다
    2. "Firebase CLI가 권한을 요청합니다" → 허용
    3. "Firebase CLI Login Successful" 이 나오면 성공입니다

  ※ 계정이 여러 개면 프로젝트를 만든 그 계정으로 로그인하세요.
'@ }
    'vercel' { @'
  터미널에서 로그인 방법을 고르라고 합니다.

    > Continue with GitHub   ← 깃허브로 가입했다면 이것
      Continue with Email

  브라우저가 열리면 Authorize 를 누르세요.
'@ }
    'supabase' { @'
  브라우저에 Supabase 로그인 화면이 열립니다.

    1. 로그인하면 토큰 생성 화면이 나옵니다
    2. Generate token 을 누릅니다
    3. 나온 긴 문자열을 복사합니다
    4. 터미널로 돌아와 붙여넣고 엔터

  ※ 붙여넣어도 화면에 글자가 안 보이는 것이 정상입니다.
'@ }
    'netlify' { @'
  브라우저에 Netlify 인증 화면이 열립니다.

    1. 로그인합니다 (깃허브 계정으로도 됩니다)
    2. "Authorize" 를 누릅니다
'@ }
  }
}

function Show-ProjectGuide([string]$s) {
  switch ($s) {
    'firebase' { @'
  Firebase 는 로그인만으로는 쓸 수 없습니다. 프로젝트를 먼저 만들어야 합니다.
  이미 만드셨다면 건너뛰세요.

    1. 브라우저에 열린 콘솔에서 "프로젝트 만들기"
    2. 이름을 정합니다 (영문 소문자와 하이픈이 안전합니다)
    3. Google 애널리틱스는 "사용 안 함" 으로 두어도 됩니다
    4. 1~2분 기다리면 완성됩니다

  작업 폴더와 연결할 때:  firebase use --add
'@ }
    'supabase' { @'
  Supabase 도 프로젝트를 먼저 만들어야 데이터베이스가 생깁니다.

    1. 대시보드에서 "New project"
    2. 조직이 없으면 하나 만듭니다
    3. 프로젝트 이름과 데이터베이스 비밀번호를 정합니다
       ⚠️ 이 비밀번호는 다시 볼 수 없습니다. 지금 적어 두세요
    4. 지역은 Northeast Asia (Seoul) 이 가장 빠릅니다
    5. 2~3분 기다리면 완성됩니다

  작업 폴더와 연결할 때:  supabase link --project-ref <프로젝트 ID>
'@ }
  }
}

# ── report: 아카이브에 담을 연결 목록 ─────────────────────────────
if ($Mode -eq 'report') {
  Write-Output "# 연결된 서비스"
  Write-Output ""
  Write-Output "새 컴퓨터에서는 아래 서비스에 **본인 계정으로 다시 로그인**해야 합니다."
  Write-Output "토큰은 이 파일에 담기지 않습니다."
  Write-Output ""
  foreach ($s in $Services) {
    $acct = Get-Account $s
    if ($acct) {
      Write-Output ("## " + (Get-Label $s))
      Write-Output ("- 계정 ``" + (Show $acct) + "`` 로 연결돼 있었습니다")
      if ($s -eq 'github' -and $acct -match ',') {
        Write-Output "- ⚠️ 계정이 여러 개입니다. 새 컴퓨터에서도 각각 로그인한 뒤, 저장소마다 활성 계정을 맞춰야 push 가 됩니다."
      }
      Write-Output ""
    }
  }
  Write-Output "## 프로젝트별 설정은 옮기지 않습니다"
  Write-Output ""
  Write-Output "``.env``, ``.firebaserc``, ``.vercel/project.json`` 같은 파일은 각 프로젝트 저장소에 속합니다."
  exit 0
}

# ── check: 상태만 보기 ────────────────────────────────────────────
if ($Mode -eq 'check') {
  Say "서비스 연결 상태"
  Say ""
  foreach ($s in $Services) {
    $label = (Get-Label $s).PadRight(10)
    if (-not (Have (Get-Cli $s))) { Dim "$label 설치 안 됨   $(Get-InstallCmd $s)"; continue }
    $acct = Get-Account $s
    if ($acct) { OK "$label 연결됨  $acct" } else { Warn "$label 로그인 필요   $(Get-LoginCmd $s)" }
  }
  Say ""
  Dim "연결을 도와드릴까요?  -Mode wizard"
  exit 0
}

# ── wizard ────────────────────────────────────────────────────────
Say ""
Say "백엔드·배포 서비스 연결 도우미"
Say ""
Say "쓰시는 서비스만 하나씩 연결합니다. 안 쓰는 것은 건너뛰셔도 됩니다."
Say "비밀번호는 이 도구가 볼 수 없습니다. 로그인은 본인 브라우저에서만 이루어집니다."
Say ""

$done = @(); $left = @()
$i = 0
foreach ($s in $Services) {
  $i++
  $label = Get-Label $s
  Say "─────────────────────────────────────────────────────────"
  Say "[$i/$($Services.Count)] $label — $(Get-Why $s)"
  Say ""

  $acct = Get-Account $s
  if ($acct) { OK "이미 연결돼 있습니다 — $acct"; $done += $label; Say ""; continue }

  $use = Read-Host "  $label 을(를) 쓰시나요? [y/N]"
  if ($use -notmatch '^[Yy]$') { Dim "건너뜁니다."; $left += $label; Say ""; continue }

  if (-not (Have (Get-Cli $s))) {
    Say ""
    Say "  먼저 $label 프로그램을 설치해야 합니다."
    Say ""
    Say "      $(Get-InstallCmd $s)"
    Say ""
    $ins = Read-Host "  지금 설치할까요? [y/N]"
    if ($ins -match '^[Yy]$') {
      Say "  설치 중입니다. 몇 분 걸릴 수 있습니다..."
      Invoke-Expression (Get-InstallCmd $s)
      if (-not (Have (Get-Cli $s))) {
        Warn "설치를 확인하지 못했습니다. 창을 닫았다가 새로 열고 다시 시도해 보세요."
        $left += $label; Say ""; continue
      }
      OK "설치했습니다."
    } else { Dim "나중에 위 명령으로 설치하세요."; $left += $label; Say ""; continue }
  }

  Say ""
  Say "  계정이 아직 없으시면 먼저 만드셔야 합니다."
  Dim "가입 주소: $(Get-SignupUrl $s)"
  $op = Read-Host "  가입 페이지를 열어드릴까요? [y/N]"
  if ($op -match '^[Yy]$') {
    Start-Process (Get-SignupUrl $s)
    OK "브라우저를 열었습니다."
    Read-Host "  다 하셨으면 엔터를 누르세요" | Out-Null
  }

  $pg = Show-ProjectGuide $s
  if ($pg) {
    Say ""
    Say $pg
    Read-Host "  다 하셨으면 엔터를 누르세요" | Out-Null
  }

  Say ""
  Say "  이제 로그인합니다."
  Say ""
  Say (Show-LoginGuide $s)
  Say ""
  Say "  아래 명령을 실행합니다. 화면 안내를 따라가세요."
  Say "      $(Get-LoginCmd $s)"
  Say ""
  $go = Read-Host "  지금 실행할까요? [y/N]"
  if ($go -match '^[Yy]$') {
    Invoke-Expression (Get-LoginCmd $s)
  } else { Dim "나중에 위 명령을 직접 실행하세요."; $left += $label; Say ""; continue }

  Say ""
  Say "  정말 연결됐는지 확인합니다..."
  $acct = Get-Account $s
  if ($acct) { OK "$label 연결 완료 — $acct"; $done += $label }
  else {
    Warn "아직 연결되지 않았습니다."
    Dim "다시 하시려면:  $(Get-LoginCmd $s)"
    Dim "로그인 창을 닫으셨거나, 브라우저에서 승인을 안 누르신 경우가 많습니다."
    $left += $label
  }
  Say ""
}

Say "═════════════════════════════════════════════════════════"
Say "정리"
Say ""
if ($done.Count) { OK ("연결됨: " + ($done -join ', ')) }
if ($left.Count) { Dim ("남음: " + ($left -join ', ')) }
Say ""
Dim "언제든 다시 확인:  -Mode check"
Dim "프로젝트별 .env 값은 각 프로젝트 안내를 따르세요. 이 도구는 계정 연결까지만 돕습니다."
