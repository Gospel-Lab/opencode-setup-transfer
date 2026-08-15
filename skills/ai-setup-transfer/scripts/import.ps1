# AI 도구 세팅 가져오기 (Windows)
#
#   powershell -ExecutionPolicy Bypass -File import.ps1
#
# 기본은 묻지 않고 전부 적용한다. 기존 파일은 백업한 뒤 덮어쓴다.
# 항목마다 확인하려면 -Ask 를 붙인다.
[CmdletBinding()]
param(
  [string]$From = '',
  [switch]$Ask,
  [string]$ConfigDir = ''
)

$ErrorActionPreference = 'Stop'
function Say($m)  { Write-Host $m }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Bad($m)  { Write-Host $m -ForegroundColor Red }
function OK($m)   { Write-Host $m -ForegroundColor Green }

$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

function Get-DestDir([string]$Tool) {
  if ($ConfigDir -and $Tool -eq 'opencode') { return $ConfigDir }
  switch ($Tool) {
    'opencode' {
      if (Get-Command opencode -ErrorAction SilentlyContinue) {
        try {
          $line = (& opencode debug paths 2>$null | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1)
          if ($line) {
            $p = ($line -replace '^\s*config\s+', '').Trim()
            if ($p) { return $p }
          }
        } catch { }
      }
      return (Join-Path $HomeDir '.config\opencode')
    }
    'claude' { if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR } else { return (Join-Path $HomeDir '.claude') } }
    'codex'  { if ($env:CODEX_HOME) { return $env:CODEX_HOME } else { return (Join-Path $HomeDir '.codex') } }
  }
}
function Get-ToolLabel([string]$Tool) {
  switch ($Tool) { 'opencode' {'opencode'} 'claude' {'Claude Code'} 'codex' {'codex'} default {$Tool} }
}

function Confirm-Step([string]$Question) {
  if (-not $Ask) { return $true }
  $r = Read-Host "$Question [y/N]"
  return ($r -match '^[Yy]$')
}

# ── 아카이브 위치 찾기 ────────────────────────────────────────────
$Src = $From
if (-not $Src) { $Src = $PSScriptRoot }

$TempExtract = $null
if ((Test-Path -LiteralPath $Src) -and -not (Get-Item -LiteralPath $Src).PSIsContainer) {
  $TempExtract = Join-Path ([System.IO.Path]::GetTempPath()) ("aiimp-" + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $TempExtract | Out-Null
  & tar -xzf $Src -C $TempExtract
  if ($LASTEXITCODE -ne 0) { Bad "오류: 압축을 풀지 못했습니다."; exit 1 }
  # 새 이름과 옛 이름 모두 받아들인다
  $cand = Get-ChildItem -LiteralPath $TempExtract -Directory | Where-Object { $_.Name -in @('ai-setup','opencode-setup') } | Select-Object -First 1
  if (-not $cand) { Bad "오류: 아카이브에서 세팅 폴더를 찾지 못했습니다."; exit 1 }
  $Src = $cand.FullName
}

$Pay = Join-Path $Src 'payload'
if (-not (Test-Path -LiteralPath $Pay)) { Bad "오류: $Pay 가 없습니다."; exit 1 }

$manifest = Join-Path $Src 'MANIFEST.md'
if (Test-Path -LiteralPath $manifest) {
  Say "==================== 아카이브 정보 ===================="
  Get-Content -LiteralPath $manifest | ForEach-Object { Say $_ }
  Say "======================================================"
}
Say ""
if (-not $Ask) { Say "== 자동 적용 모드 (항목마다 확인하려면 -Ask)" }

# ── 작업 사본을 만들고 경로를 이 컴퓨터 기준으로 되돌린다 ──────────
$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("aiwork-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
# -LiteralPath 는 와일드카드를 해석하지 않는다. 폴더째 옮길 때는 항목을 하나씩 복사한다.
Get-ChildItem -LiteralPath $Pay -Force | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Work $_.Name) -Recurse -Force
}

Say "== 절대경로 복원 ({{HOME}} → $HomeDir)"
$textExt = @('.md','.json','.jsonc','.toml','.txt','.sh','.ps1','.js','.ts','.yml','.yaml','.cfg','.ini')
Get-ChildItem -LiteralPath $Work -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  if ($textExt -contains $_.Extension.ToLower()) {
    try {
      $c = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
      if ($c -and $c.Contains('{{HOME}}')) {
        Set-Content -LiteralPath $_.FullName -Value $c.Replace('{{HOME}}', $HomeDir) -Encoding UTF8
      }
    } catch { }
  }
}

$Backup = Join-Path (Get-DestDir 'opencode') ("backups\import-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $Backup | Out-Null

# ── 담긴 도구 파악 ────────────────────────────────────────────────
$Tools = @()
$toolsFile = Join-Path $Src '.tools'
if (Test-Path -LiteralPath $toolsFile) {
  $Tools = (Get-Content -LiteralPath $toolsFile -Raw).Trim() -split '\s+' | Where-Object { $_ }
}
if (-not $Tools) {
  foreach ($t in @('opencode','claude','codex')) {
    if (Test-Path -LiteralPath (Join-Path $Work $t)) { $Tools += $t }
  }
  # 아주 옛 형식: 도구 폴더 없이 최상위에 opencode 파일이 있던 때
  if (-not $Tools -and (Test-Path -LiteralPath (Join-Path $Work 'skills'))) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Work 'opencode') | Out-Null
    Get-ChildItem -LiteralPath $Work -Force | Where-Object { $_.Name -ne 'opencode' } |
      ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Work 'opencode') -Force }
    $Tools = @('opencode')
  }
  $ext = Join-Path $Work 'external-claude-skills'
  if (Test-Path -LiteralPath $ext) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Work 'claude') | Out-Null
    Move-Item -LiteralPath $ext -Destination (Join-Path $Work 'claude\skills') -Force
    if ($Tools -notcontains 'claude') { $Tools += 'claude' }
  }
}

function Merge-Folder([string]$SrcDir, [string]$DstDir, [string]$Label, [string]$Tool) {
  if (-not (Test-Path -LiteralPath $SrcDir)) { return }
  $files = @(Get-ChildItem -LiteralPath $SrcDir -Recurse -File -Force -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) { return }

  $conflicts = @()
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($SrcDir.Length).TrimStart('\','/')
    if (Test-Path -LiteralPath (Join-Path $DstDir $rel)) { $conflicts += $rel }
  }
  Say ""
  Say "--- $Label ($($files.Count)개 파일)"
  if ($conflicts.Count) {
    Say "  이미 있는 파일 $($conflicts.Count)개"
    $conflicts | Select-Object -First 5 | ForEach-Object { Say "    $_" }
    if ($conflicts.Count -gt 5) { Say "    ... 외 $($conflicts.Count - 5)개" }
  }
  if (-not (Confirm-Step "  $Label 을(를) 가져올까요?")) { Say "  건너뜀"; return }

  $overwrite = $true
  if ($conflicts.Count -and $Ask) { $overwrite = Confirm-Step "  기존 파일을 덮어쓸까요? (아니오 = 없는 것만 추가)" }

  if ($conflicts.Count -and $overwrite) {
    $bk = Join-Path $Backup $Tool
    New-Item -ItemType Directory -Force -Path $bk | Out-Null
    foreach ($rel in $conflicts) {
      $t = Join-Path $DstDir $rel
      $b = Join-Path $bk $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $b -Parent) | Out-Null
      Copy-Item -LiteralPath $t -Destination $b -Force -ErrorAction SilentlyContinue
    }
  }
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($SrcDir.Length).TrimStart('\','/')
    $dst = Join-Path $DstDir $rel
    if ((Test-Path -LiteralPath $dst) -and -not $overwrite) { continue }
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
  }
  if ($conflicts.Count -and $overwrite) { Say "  덮어쓰기 완료 (기존본 백업: $Backup)" }
  else { Say "  적용 완료" }
}

function Merge-JsonConfig([string]$SrcFile, [string]$DstFile) {
  # 주석을 걷어낸 뒤 병합한다. 원본은 백업에 남으므로 주석은 거기서 확인할 수 있다.
  function Strip-Comments([string]$t) {
    $out = New-Object System.Text.StringBuilder
    $inStr = $false; $esc = $false; $i = 0
    while ($i -lt $t.Length) {
      $c = $t[$i]
      if ($inStr) {
        [void]$out.Append($c)
        if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
        $i++; continue
      }
      if ($c -eq '"') { $inStr = $true; [void]$out.Append($c); $i++; continue }
      if ($c -eq '/' -and $i + 1 -lt $t.Length) {
        if ($t[$i+1] -eq '/') { while ($i -lt $t.Length -and $t[$i] -ne "`n") { $i++ }; continue }
        if ($t[$i+1] -eq '*') { $j = $t.IndexOf('*/', $i + 2); if ($j -lt 0) { $i = $t.Length } else { $i = $j + 2 }; continue }
      }
      [void]$out.Append($c); $i++
    }
    return ($out.ToString() -replace ',(\s*[}\]])', '$1')
  }
  function ToHash($o) {
    if ($o -is [System.Management.Automation.PSCustomObject]) {
      $h = @{}
      foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ToHash $p.Value }
      return $h
    }
    return $o
  }
  function DeepMerge($a, $b) {
    if ($a -isnot [hashtable] -or $b -isnot [hashtable]) { return $b }
    $r = @{}
    foreach ($k in $a.Keys) { $r[$k] = $a[$k] }
    foreach ($k in $b.Keys) {
      if ($r.ContainsKey($k) -and $r[$k] -is [hashtable] -and $b[$k] -is [hashtable]) { $r[$k] = DeepMerge $r[$k] $b[$k] }
      else { $r[$k] = $b[$k] }
    }
    return $r
  }
  $new = ToHash ((Strip-Comments (Get-Content -LiteralPath $SrcFile -Raw)) | ConvertFrom-Json)
  $cur = @{}
  if (Test-Path -LiteralPath $DstFile) {
    $curText = Strip-Comments (Get-Content -LiteralPath $DstFile -Raw)
    if ($curText.Trim()) { $cur = ToHash ($curText | ConvertFrom-Json) }
  }
  $merged = DeepMerge $cur $new
  $merged | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $DstFile -Encoding UTF8
  Say "  병합 완료 (기존본은 백업에 있습니다)"
}

function Show-Redacted([string]$File) {
  if (-not (Test-Path -LiteralPath $File)) { return }
  try {
    $c = Get-Content -LiteralPath $File -Raw
    $found = [regex]::Matches($c, '<<<REDACTED:([^>]*)>>>') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($r in $found) { Say "    직접 채워야 함: $r" }
  } catch { }
}

# ── 도구별 적용 ───────────────────────────────────────────────────
$Applied = @()
foreach ($tool in $Tools) {
  $tw = Join-Path $Work $tool
  if (-not (Test-Path -LiteralPath $tw)) { continue }
  $dest = Get-DestDir $tool
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Say ""
  Say "═══ $(Get-ToolLabel $tool) → $dest"

  $configNames = @('opencode.json','opencode.jsonc','settings.json','config.toml')
  Get-ChildItem -LiteralPath $tw -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -eq 'PLUGINS.txt') { return }
    if ($configNames -contains $_.Name) { return }
    if ($_.PSIsContainer) {
      Merge-Folder $_.FullName (Join-Path $dest $_.Name) "$($_.Name)/" $tool
    } else {
      $dst = Join-Path $dest $_.Name
      Say ""
      if (Test-Path -LiteralPath $dst) {
        Say "--- $($_.Name) (이미 있음)"
        if (Confirm-Step "  덮어쓸까요? (기존본은 백업됩니다)") {
          $bk = Join-Path $Backup $tool
          New-Item -ItemType Directory -Force -Path $bk | Out-Null
          Copy-Item -LiteralPath $dst -Destination (Join-Path $bk $_.Name) -Force -ErrorAction SilentlyContinue
          Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
          Say "  덮어썼습니다"
        } else { Say "  건너뜀" }
      } else {
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        Say "--- $($_.Name)  복사 완료"
      }
    }
  }

  # 설정 파일 — 형식마다 다루는 법이 다르다
  switch ($tool) {
    'opencode' {
      $srcCfg = @('opencode.jsonc','opencode.json') | Where-Object { Test-Path -LiteralPath (Join-Path $tw $_) } | Select-Object -First 1
      if ($srcCfg) {
        $dstName = @('opencode.jsonc','opencode.json') | Where-Object { Test-Path -LiteralPath (Join-Path $dest $_) } | Select-Object -First 1
        if (-not $dstName) { $dstName = $srcCfg }
        $dstFile = Join-Path $dest $dstName
        Say ""
        Say "--- $dstName"
        if (Confirm-Step "  적용할까요?") {
          if (Test-Path -LiteralPath $dstFile) {
            New-Item -ItemType Directory -Force -Path (Join-Path $Backup $tool) | Out-Null
            Copy-Item -LiteralPath $dstFile -Destination (Join-Path $Backup "$tool\$dstName") -Force
            Merge-JsonConfig (Join-Path $tw $srcCfg) $dstFile
          } else {
            Copy-Item -LiteralPath (Join-Path $tw $srcCfg) -Destination $dstFile -Force
            Say "  복사 완료 (주석까지 그대로)"
          }
          Show-Redacted $dstFile
        }
      }
    }
    'claude' {
      $s = Join-Path $tw 'settings.json'
      if (Test-Path -LiteralPath $s) {
        $d = Join-Path $dest 'settings.json'
        Say ""
        Say "--- settings.json"
        if (Confirm-Step "  적용할까요?") {
          if (Test-Path -LiteralPath $d) {
            New-Item -ItemType Directory -Force -Path (Join-Path $Backup $tool) | Out-Null
            Copy-Item -LiteralPath $d -Destination (Join-Path $Backup "$tool\settings.json") -Force
            Merge-JsonConfig $s $d
          } else {
            Copy-Item -LiteralPath $s -Destination $d -Force
            Say "  복사 완료"
          }
          Show-Redacted $d
        }
      }
    }
    'codex' {
      $s = Join-Path $tw 'config.toml'
      if (Test-Path -LiteralPath $s) {
        $d = Join-Path $dest 'config.toml'
        Say ""
        Say "--- config.toml"
        if (Test-Path -LiteralPath $d) {
          # TOML 은 안전한 자동 병합이 어렵다. 덮어쓰지 않고 나란히 둔다.
          New-Item -ItemType Directory -Force -Path (Join-Path $Backup $tool) | Out-Null
          Copy-Item -LiteralPath $d -Destination (Join-Path $Backup "$tool\config.toml") -Force
          Copy-Item -LiteralPath $s -Destination "$d.from-old-machine" -Force
          Say "  이 컴퓨터에 이미 설정이 있어 덮어쓰지 않았습니다."
          Say "  옛 설정은 config.toml.from-old-machine 으로 두었습니다. 필요한 줄만 옮겨 쓰세요."
        } else {
          Copy-Item -LiteralPath $s -Destination $d -Force
          Say "  복사 완료 (주석까지 그대로)"
          Show-Redacted $d
        }
      }
    }
  }
  $Applied += $tool
}

# ── 확인 ──────────────────────────────────────────────────────────
Say ""
Say "== 적용 결과 확인"
foreach ($tool in $Applied) {
  switch ($tool) {
    'opencode' {
      if (Get-Command opencode -ErrorAction SilentlyContinue) {
        & opencode debug config *> $null
        if ($LASTEXITCODE -eq 0) { OK "  opencode: 설정 정상" }
        else { Warn "  ⚠️ opencode: 설정을 읽지 못했습니다 → opencode debug config 로 확인하세요" }
      } else { Say "  opencode: 아직 설치되지 않음 (설정만 넣어두었습니다)" }
    }
    'claude' {
      $sk = Join-Path (Get-DestDir 'claude') 'skills'
      $n = if (Test-Path $sk) { (Get-ChildItem -LiteralPath $sk -Directory | Measure-Object).Count } else { 0 }
      if (Get-Command claude -ErrorAction SilentlyContinue) { OK "  Claude Code: 설치됨 · 스킬 ${n}개" }
      else { Say "  Claude Code: 아직 설치되지 않음 · 스킬 ${n}개 넣어두었습니다" }
    }
    'codex' {
      $sk = Join-Path (Get-DestDir 'codex') 'skills'
      $n = if (Test-Path $sk) { (Get-ChildItem -LiteralPath $sk -Directory | Measure-Object).Count } else { 0 }
      if (Get-Command codex -ErrorAction SilentlyContinue) { OK "  codex: 설치됨 · 스킬 ${n}개" }
      else { Say "  codex: 아직 설치되지 않음 · 스킬 ${n}개 넣어두었습니다" }
    }
  }
}

$conn = Join-Path $Src 'CONNECTIONS.md'
if (Test-Path -LiteralPath $conn) {
  Say ""
  Say "== 연결해야 할 서비스"
  Get-Content -LiteralPath $conn | ForEach-Object { Say "  $_" }
}

Say ""
Say "==================== 남은 작업 ===================="
$n = 1
foreach ($tool in $Applied) {
  switch ($tool) {
    'opencode' {
      Say "$n. opencode auth login  — AI 제공자에 본인 키로 연결"; $n++
      $pl = Join-Path $Work 'opencode\PLUGINS.txt'
      if (Test-Path -LiteralPath $pl) { Say "$n. opencode 플러그인 설치:"; Get-Content $pl | ForEach-Object { Say "     $_" }; $n++ }
    }
    'claude' {
      $pl = Join-Path $Work 'claude\PLUGINS.txt'
      if (Test-Path -LiteralPath $pl) { Say "$n. Claude Code 플러그인 설치:"; Get-Content $pl | ForEach-Object { Say "     $_" }; $n++ }
    }
    'codex' { Say "$n. codex 로그인 (codex 실행 후 안내를 따르세요)"; $n++ }
  }
}
Say "$n. 설정 파일의 <<<REDACTED:...>>> 값 직접 채우기"; $n++
$cw = Join-Path $Src 'connect.ps1'
if (Test-Path -LiteralPath $cw) {
  Say "$n. 서비스 연결 — 아래를 실행하면 하나씩 안내합니다:"; $n++
  Say "     powershell -ExecutionPolicy Bypass -File `"$cw`" -Mode wizard"
}
Say "$n. 각 도구를 종료했다가 다시 실행 (설정은 시작할 때 한 번만 읽습니다)"
Say ""
Say "가져오기 전 상태 백업: $Backup"

Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
if ($TempExtract) { Remove-Item -LiteralPath $TempExtract -Recurse -Force -ErrorAction SilentlyContinue }
