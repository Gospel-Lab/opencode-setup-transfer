# AI 도구 세팅 내보내기 (Windows)
#
#   powershell -ExecutionPolicy Bypass -File export.ps1
#
# 이 컴퓨터에 깔려 있는 AI 도구를 찾아 설정을 파일 하나로 포장한다.
# API 키·대화 기록·캐시는 담지 않는다.
[CmdletBinding()]
param(
  [ValidateSet('personal','share')][string]$Mode = 'personal',
  [string]$Out = '',
  [string[]]$Exclude = @(),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
function Say($m)  { Write-Host $m }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Bad($m)  { Write-Host $m -ForegroundColor Red }

$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

# PowerShell 5.1 의 -Encoding UTF8 은 BOM 을 붙인다.
# BOM 이 붙은 JSON 은 다른 도구(파이썬 등)가 읽다가 실패하므로 항상 BOM 없이 쓴다.
function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}


# ── 이 컴퓨터에 깔린 도구를 찾는다 ────────────────────────────────
# 만든 사람 환경이 아니라 쓰는 사람 환경 기준이다.
function Get-ToolDir([string]$Tool) {
  switch ($Tool) {
    'opencode' {
      if (Get-Command opencode -ErrorAction SilentlyContinue) {
        try {
          $line = (& opencode debug paths 2>$null | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1)
          if ($line) {
            $p = ($line -replace '^\s*config\s+', '').Trim()
            if ($p -and (Test-Path $p)) { return $p }
          }
        } catch { }
      }
      $p = Join-Path $HomeDir '.config\opencode'
      if (Test-Path $p) { return $p }
      return $null
    }
    'claude' {
      $p = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HomeDir '.claude' }
      if (Test-Path $p) { return $p }
      return $null
    }
    'codex' {
      $p = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HomeDir '.codex' }
      if (Test-Path $p) { return $p }
      return $null
    }
  }
  return $null
}

function Get-ToolLabel([string]$Tool) {
  switch ($Tool) { 'opencode' {'opencode'} 'claude' {'Claude Code'} 'codex' {'codex'} default {$Tool} }
}

# 담을 것만 적는다(화이트리스트). 대화 기록·로그·캐시·인증 파일은 후보에 없다.
function Get-ToolItems([string]$Tool) {
  switch ($Tool) {
    'opencode' { @('opencode.json','opencode.jsonc','tui.json','package.json','AGENTS.md',
                   'agent','agents','command','commands','skill','skills',
                   'theme','themes','mode','modes','plugin','plugins') }
    'claude'   { @('settings.json','CLAUDE.md','statusline.sh','skills','commands','hooks','scripts') }
    'codex'    { @('config.toml','AGENTS.md','skills','prompts') }
  }
}

function Get-PersonalOnly([string]$Tool) {
  switch ($Tool) { 'opencode' { @('AGENTS.md') } 'claude' { @('CLAUDE.md') } 'codex' { @('AGENTS.md') } }
}

$SkipDirs  = @('node_modules','venv','.venv','dist','build','.next','coverage','__pycache__','.pytest_cache','.git')
$SkipFiles = @('*.log','*.pyc','.DS_Store')
$BigLimitMB = 5

function Copy-Whitelisted([string]$Src, [string]$Dst) {
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null
  Get-ChildItem -LiteralPath $Src -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.PSIsContainer) {
      if ($SkipDirs -contains $_.Name) { return }
      if ($Exclude -contains $_.Name)  { return }
      Copy-Whitelisted $_.FullName (Join-Path $Dst $_.Name)
    } else {
      foreach ($pat in $SkipFiles) { if ($_.Name -like $pat) { return } }
      if ($Exclude -contains $_.Name) { return }
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dst $_.Name) -Force -ErrorAction SilentlyContinue
    }
  }
}

$Stamp = Get-Date -Format 'yyyyMMdd'
if (-not $Out) {
  $desktop = Join-Path $HomeDir 'Desktop'
  $dir = if (Test-Path $desktop) { $desktop } else { $HomeDir }
  $Out = Join-Path $dir "ai-setup-$Mode-$Stamp.tar.gz"
}

$Work  = Join-Path ([System.IO.Path]::GetTempPath()) ("aisetup-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$Stage = Join-Path $Work 'ai-setup'
$Pay   = Join-Path $Stage 'payload'
New-Item -ItemType Directory -Force -Path $Pay | Out-Null

Say "== 1/6 파일 수집 (모드: $Mode)"

$Found = @()
$SymNotes = @()
foreach ($tool in @('opencode','claude','codex')) {
  $dir = Get-ToolDir $tool
  if (-not $dir) { continue }

  $tdir = Join-Path $Pay $tool
  $personalOnly = Get-PersonalOnly $tool
  $copied = $false

  foreach ($item in (Get-ToolItems $tool)) {
    $src = Join-Path $dir $item
    if (-not (Test-Path -LiteralPath $src)) { continue }
    if ($Mode -eq 'share' -and $personalOnly -contains $item) { continue }
    if ($Exclude -contains $item) { continue }

    $info = Get-Item -LiteralPath $src -Force
    if ($info.PSIsContainer) {
      # 너무 큰 폴더는 담지 않는다. 도구를 따로 설치하는 편이 낫다.
      $sizeMB = 0
      try {
        $sizeMB = [math]::Round(((Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum / 1MB), 1)
      } catch { $sizeMB = 0 }
      if ($sizeMB -gt $BigLimitMB) {
        $SymNotes += "- [$tool/$item] ${sizeMB}MB — **제외**, 새 컴퓨터에 원본 도구를 따로 설치하세요"
        continue
      }
      New-Item -ItemType Directory -Force -Path $tdir | Out-Null
      Copy-Whitelisted $src (Join-Path $tdir $item)
      $copied = $true
    } else {
      New-Item -ItemType Directory -Force -Path $tdir | Out-Null
      Copy-Item -LiteralPath $src -Destination (Join-Path $tdir $item) -Force
      $copied = $true
    }
  }

  if (-not $copied) { continue }
  $n = (Get-ChildItem -LiteralPath $tdir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
  if ($n -eq 0) { Remove-Item -LiteralPath $tdir -Recurse -Force -ErrorAction SilentlyContinue; continue }
  $Found += $tool
  Say ("  " + (Get-ToolLabel $tool) + " — $dir (${n}개 파일)")
}

if ($Found.Count -eq 0) {
  Bad "오류: 옮길 AI 도구 설정을 찾지 못했습니다."
  Bad "  opencode, Claude Code, codex 중 하나라도 설정이 있어야 합니다."
  Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
Write-Utf8NoBom (Join-Path $Stage '.tools') ($Found -join ' ')

Say "== 2/6 설정 파일의 비밀값 제거"

# 구조를 아는 JSON 은 정확히 짚어 지운다
$ocJson = Join-Path $Pay 'opencode\opencode.json'
if (Test-Path -LiteralPath $ocJson) {
  try {
    $cfg = Get-Content -LiteralPath $ocJson -Raw | ConvertFrom-Json
    $hits = @()
    if ($cfg.provider) {
      foreach ($pv in $cfg.provider.PSObject.Properties) {
        if ($pv.Value.options) {
          foreach ($op in @($pv.Value.options.PSObject.Properties)) {
            if ($op.Name -match '(?i)key|token') {
              $pv.Value.options."$($op.Name)" = "<<<REDACTED:provider.$($pv.Name).options.$($op.Name)>>>"
              $hits += $op.Name
            }
          }
        }
      }
    }
    if ($cfg.mcp) {
      foreach ($sv in $cfg.mcp.PSObject.Properties) {
        foreach ($fieldName in @('headers','environment')) {
          $blk = $sv.Value.$fieldName
          if ($blk) {
            foreach ($kv in @($blk.PSObject.Properties)) {
              if ($kv.Name -match '(?i)key|token|auth|secret' -and $kv.Value -is [string] -and $kv.Value -notlike '{env:*') {
                $blk."$($kv.Name)" = "<<<REDACTED:mcp.$($sv.Name).$fieldName.$($kv.Name)>>>"
                $hits += $kv.Name
              }
            }
          }
        }
      }
    }
Write-Utf8NoBom $ocJson ((    $cfg | ConvertTo-Json -Depth 20 ) -join "`n")
    if ($hits.Count) { Say ("  opencode.json: 치환 " + (($hits | Sort-Object -Unique) -join ', ')) }
    else { Say "  opencode.json: 비밀값 없음" }

    if ($cfg.plugin) {
      $lines = @()
      foreach ($pl in $cfg.plugin) {
        $m = if ($pl -is [array]) { $pl[0] } else { $pl }
        if ($m -is [string] -and $m -notmatch '^(\.|file:)') { $lines += "opencode plugin $m" }
      }
      if ($lines.Count) { Write-Utf8NoBom (Join-Path $Pay 'opencode\PLUGINS.txt') (($lines -join "`n") + "`n") }
    }
  } catch { Warn "  ⚠️ opencode.json 을 읽지 못했습니다: $_" }
}

# 주석이 있는 형식은 값만 바꾼다. 구조를 다시 쓰면 사용자가 적어둔 주석이 사라진다.
$secretKeyPat = '(?i)(["'']?)([A-Za-z_]*(?:apikey|api_key|token|secret|password|authorization|credential)[A-Za-z_]*)(["'']?\s*[:=]\s*["''])(?!\{env:)(?!<<<REDACTED)(?![/~.])([^"''\r\n]{8,})(["''])'
foreach ($rel in @('opencode\opencode.jsonc','codex\config.toml','claude\settings.json')) {
  $f = Join-Path $Pay $rel
  if (-not (Test-Path -LiteralPath $f)) { continue }
  $t = Get-Content -LiteralPath $f -Raw
  $hits = @()
  $t2 = [regex]::Replace($t, $secretKeyPat, {
    param($m)
    $script:__k = $m.Groups[2].Value
    $hits += $script:__k
    $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value + "<<<REDACTED:$($m.Groups[2].Value)>>>" + $m.Groups[5].Value
  })
  if ($hits.Count) {
    Write-Utf8NoBom $f $t2
    Say ("  " + (Split-Path $rel -Leaf) + ": 치환 " + (($hits | Sort-Object -Unique) -join ', '))
  } else {
    Say ("  " + (Split-Path $rel -Leaf) + ": 비밀값 없음")
  }
}

# Claude Code 플러그인 목록 → 재설치 명령
$clSettings = Join-Path $Pay 'claude\settings.json'
if (Test-Path -LiteralPath $clSettings) {
  try {
    $d = Get-Content -LiteralPath $clSettings -Raw | ConvertFrom-Json
    $lines = @()
    if ($d.extraKnownMarketplaces) {
      foreach ($mp in $d.extraKnownMarketplaces.PSObject.Properties) {
        if ($mp.Value.source.source -eq 'github' -and $mp.Value.source.repo) {
          $lines += "claude plugin marketplace add $($mp.Value.source.repo)"
        }
      }
    }
    if ($d.enabledPlugins) {
      foreach ($pg in $d.enabledPlugins.PSObject.Properties) {
        if ($pg.Value) { $lines += "claude plugin install $($pg.Name)" }
      }
    }
    if ($lines.Count) {
      Write-Utf8NoBom (Join-Path $Pay 'claude\PLUGINS.txt') (($lines -join "`n") + "`n")
      Say "  Claude Code 플러그인 $($lines.Count)개 목록 기록"
    }
  } catch { }
}

Say "== 3/6 연결 서비스 목록 작성"
$connPs = Join-Path $PSScriptRoot 'connect.ps1'
if (Test-Path -LiteralPath $connPs) {
  try {
    $rep = & $connPs -Mode report -Masked:($Mode -eq 'share') 6>$null
    Write-Utf8NoBom (Join-Path $Stage 'CONNECTIONS.md') (($rep -join "`n") + "`n")
    Say "  기록 완료 (토큰은 담기지 않습니다)"
  } catch { Warn "  연결 목록을 만들지 못했습니다: $_" }
}

Say "== 4/6 절대경로 템플릿화"
# 사용자 이름이 다른 컴퓨터에서도 동작하도록 홈 경로를 자리표시자로 바꾼다
$textExt = @('.md','.json','.jsonc','.toml','.txt','.sh','.ps1','.js','.ts','.yml','.yaml','.cfg','.ini')
Get-ChildItem -LiteralPath $Pay -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  if ($textExt -contains $_.Extension.ToLower()) {
    try {
      $c = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
      if ($c -and ($c.Contains($HomeDir))) {
        $c = $c.Replace($HomeDir, '{{HOME}}')
        # 슬래시 방향이 다른 표기도 함께 바꾼다
        $c = $c.Replace($HomeDir.Replace('\','/'), '{{HOME}}')
        Write-Utf8NoBom $_.FullName $c
      }
    } catch { }
  }
}

Say "== 5/6 비밀정보·개인정보 스캔"
$keyPat = @(
  'sk-ant-[A-Za-z0-9_\-]{20,}', 'sk-proj-[A-Za-z0-9_\-]{20,}', 'sk-or-v1-[A-Za-z0-9_\-]{16,}',
  'sk-[A-Za-z0-9]{20,}', 'ghp_[A-Za-z0-9]{20,}', 'gho_[A-Za-z0-9]{20,}',
  'github_pat_[A-Za-z0-9_]{20,}', 'glpat-[A-Za-z0-9_\-]{16,}', 'xox[abprs]-[A-Za-z0-9\-]{10,}',
  'AIza[0-9A-Za-z_\-]{30,}', 'ya29\.[0-9A-Za-z_\-]{20,}', '(AKIA|ASIA)[0-9A-Z]{16}',
  'dop_v1_[a-f0-9]{32,}', 'nfp_[A-Za-z0-9]{20,}',
  'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{3,}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----',
  '[A-Za-z_]*(api[_\-]?key|secret|token|password|credential)[A-Za-z_]*["'']?\s*[:=]\s*["'']?[A-Za-z0-9/+_\-]{16,}'
) -join '|'
$fixture = '(?i)[\\/](tests?|__tests__|fixtures?|site-packages|node_modules|examples?)[\\/]|\.(test|spec)\.'

$hitsAll = @()
Get-ChildItem -LiteralPath $Pay -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $path = $_.FullName
  if ($path -match $fixture) { return }
  try { $c = Get-Content -LiteralPath $path -Raw -ErrorAction Stop } catch { return }
  if (-not $c) { return }
  foreach ($m in [regex]::Matches($c, $keyPat, 'IgnoreCase')) {
    if ($m.Value -like '*REDACTED*') { continue }
    $rel = $path.Substring($Pay.Length).TrimStart('\','/')
    $hitsAll += "$rel : $($m.Value.Substring(0, [Math]::Min(60, $m.Value.Length)))"
  }
}
if ($hitsAll.Count) {
  Warn "  ⚠️ 비밀정보 의심 $($hitsAll.Count)건:"
  $hitsAll | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" }
  if ($Mode -eq 'share' -and -not $Force) {
    Bad "  배포 모드에서는 중단합니다. -Exclude <파일명> 으로 빼거나 값을 지운 뒤 다시 실행하세요."
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    exit 2
  }
  Say "  personal 모드이므로 계속합니다. 이 파일을 남에게 주지 마세요."
} else {
  Say "  차단 대상 비밀정보 없음."
}

if ($Mode -eq 'share') {
  $ids = @()
  foreach ($v in @($env:USERNAME, $env:COMPUTERNAME,
                   (& git config --global user.email 2>$null), (& git config --global user.name 2>$null))) {
    if ($v -and $v.Length -ge 4) { $ids += [regex]::Escape($v) }
  }
  if ($ids.Count) {
    $idPat = ($ids -join '|')
    $idHits = @()
    Get-ChildItem -LiteralPath $Pay -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.FullName -match $fixture) { return }
      try { $c = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop } catch { return }
      if ($c -and ($c -match $idPat)) {
        $idHits += $_.FullName.Substring($Pay.Length).TrimStart('\','/')
      }
    }
    if ($idHits.Count) {
      Warn "  ⚠️ 본인 식별정보가 $($idHits.Count)개 파일에 있습니다:"
      $idHits | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" }
      if (-not $Force) {
        Bad "  배포 모드에서는 중단합니다. -Exclude <파일명> 으로 빼고 다시 실행하세요."
        Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
        exit 3
      }
    } else { Say "  개인 식별정보 없음." }
  }
}

Say "== 6/6 매니페스트 작성 및 압축"
$man = @()
$man += "# AI 도구 세팅 아카이브"
$man += ""
$man += "- 생성일: " + (Get-Date -Format 'yyyy-MM-dd HH:mm')
$man += "- 모드: $Mode"
$man += "- 만든 곳: Windows"
$man += "- 담긴 도구: " + ($Found -join ' ')
$man += ""
$man += "## 포함된 항목"
foreach ($t in $Found) {
  $man += ""
  $man += "### " + (Get-ToolLabel $t)
  Get-ChildItem -LiteralPath (Join-Path $Pay $t) -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.PSIsContainer) {
      $c = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
      $man += "- $($_.Name)/ (${c}개 파일)"
    } else { $man += "- $($_.Name)" }
  }
}
$man += ""
$man += "## 의도적으로 제외한 것"
$man += "- 각 도구의 인증 파일 (API 키·토큰)"
$man += "- 대화 기록·세션·로그·캐시"
$man += "- node_modules·플러그인 캐시"
$man += "- GitHub·Firebase·Vercel 등의 토큰 (계정에 묶여 있어 복사해도 동작하지 않음)"
if ($SymNotes.Count) {
  $man += ""
  $man += "## 크기 때문에 제외한 항목"
  $man += $SymNotes
}
Write-Utf8NoBom (Join-Path $Stage 'MANIFEST.md') (($man -join "`n") + "`n")

# 반대편에서 쓸 스크립트를 함께 담는다 — 새 컴퓨터에 아무것도 없어도 되도록
foreach ($f in @('import.ps1','connect.ps1','import.sh','connections.sh','connect.sh')) {
  $src = Join-Path $PSScriptRoot $f
  if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $f) -Force }
}

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }

# tar 는 Windows 10 1809+ 에 기본 포함돼 있고, 맥·리눅스와 같은 형식이라 서로 주고받을 수 있다
Push-Location $Work
try {
  & tar -czf $Out 'ai-setup'
  if ($LASTEXITCODE -ne 0) { throw "tar 압축에 실패했습니다 (코드 $LASTEXITCODE)" }
} finally { Pop-Location }

Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue

$sizeKB = [math]::Round((Get-Item -LiteralPath $Out).Length / 1KB)
Say ""
Say "완료: $Out"
Say "크기: ${sizeKB}KB"
Say ""
Say "새 컴퓨터에서:"
Say "  tar -xzf $(Split-Path $Out -Leaf)"
Say "  cd ai-setup"
Say "  powershell -ExecutionPolicy Bypass -File import.ps1"
