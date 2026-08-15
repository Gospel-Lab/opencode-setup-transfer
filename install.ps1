# AI 도구 세팅 이사 설치 (Windows)
#
#   irm https://raw.githubusercontent.com/Gospel-Lab/ai-setup-transfer/main/install.ps1 | iex
#
# 하는 일: 이 저장소의 스크립트를 설정 폴더에 넣는다. 관리자 권한은 필요 없다.
$ErrorActionPreference = 'Stop'

$Repo   = if ($env:AI_SETUP_REPO)   { $env:AI_SETUP_REPO }   else { 'Gospel-Lab/ai-setup-transfer' }
$Branch = if ($env:AI_SETUP_BRANCH) { $env:AI_SETUP_BRANCH } else { 'main' }
$Name   = 'ai-setup-transfer'

$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

# 설정 폴더는 opencode 에게 묻는다. 없으면 표준 경로를 쓴다.
$Conf = $null
if (Get-Command opencode -ErrorAction SilentlyContinue) {
  try {
    $line = (& opencode debug paths 2>$null | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1)
    if ($line) { $Conf = ($line -replace '^\s*config\s+', '').Trim() }
  } catch { }
}
if (-not $Conf) { $Conf = Join-Path $HomeDir '.config\opencode' }
$Dest = Join-Path $Conf "skills\$Name"

Write-Host "AI 도구 세팅 이사를 설치합니다."
Write-Host "  설치 위치: $Dest"

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aiinst-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
  Write-Host "  내려받는 중..."
  $zip = Join-Path $Tmp 'src.zip'
  Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/zip/refs/heads/$Branch" -OutFile $zip -UseBasicParsing
  Expand-Archive -LiteralPath $zip -DestinationPath $Tmp -Force

  # 폴더 이름이 바뀌었을 수도 있다. 이름 대신 SKILL.md 가 있는 폴더를 찾는다.
  $src = Get-ChildItem -LiteralPath $Tmp -Recurse -Filter 'SKILL.md' -ErrorAction SilentlyContinue |
         Where-Object { $_.DirectoryName -match '[\\/]skills[\\/]' } |
         Select-Object -First 1
  if (-not $src) { throw "저장소 안에서 스킬 폴더를 찾지 못했습니다." }
  $srcDir = $src.DirectoryName

  # 기존 설치본은 백업해 둔다
  if (Test-Path -LiteralPath $Dest) {
    $bk = Join-Path $Conf ("backups\tool-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $bk | Out-Null
    Copy-Item -LiteralPath $Dest -Destination $bk -Recurse -Force
    Write-Host "  기존 설치본 백업: $bk"
  }

  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Get-ChildItem -LiteralPath $srcDir -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name) -Recurse -Force
  }

  # 옛 이름으로 설치돼 있던 것은 정리한다
  $old = Join-Path $Conf 'skills\opencode-setup-transfer'
  if ((Test-Path -LiteralPath $old) -and ($old -ne $Dest)) {
    Remove-Item -LiteralPath $old -Recurse -Force
    Write-Host "  옛 이름으로 설치돼 있던 것을 정리했습니다."
  }
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$ps = Join-Path $Dest 'scripts'
Write-Host ""
Write-Host "설치 완료."
Write-Host ""
Write-Host "▸ 지금 쓰던 컴퓨터에서 — 내 세팅을 파일 하나로 포장"
Write-Host "    powershell -ExecutionPolicy Bypass -File `"$ps\export.ps1`""
Write-Host ""
Write-Host "▸ 새 컴퓨터에서 — 그 파일을 풀고 실행하면 자동 적용"
Write-Host "    tar -xzf ai-setup-personal-*.tar.gz"
Write-Host "    cd ai-setup"
Write-Host "    powershell -ExecutionPolicy Bypass -File import.ps1"
Write-Host ""
Write-Host "▸ 깃허브·파이어베이스 같은 서비스 연결"
Write-Host "    powershell -ExecutionPolicy Bypass -File `"$ps\connect.ps1`" -Mode wizard"
