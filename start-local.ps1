param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$env:NODE_ENV = 'development'

$localDir = Join-Path $projectRoot '.local'
if (!(Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir | Out-Null }

# 1. Ensure PostgreSQL service is running
$pgConnection = Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue
if (!$pgConnection) {
  Write-Output 'Starting PostgreSQL service...'
  Get-Service -Name '*postgres*' | Start-Service -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

# 2. Build backend if needed
if ($Rebuild -or !(Test-Path (Join-Path $projectRoot 'backend\dist\index.js'))) {
  Write-Output 'Building backend...'
  & npm.cmd run build --prefix (Join-Path $projectRoot 'backend')
  if ($LASTEXITCODE -ne 0) { throw 'Backend build failed.' }
}

# 3. Resolve Flutter executable and build web if needed
$flutterExe = 'flutter.bat'
if (!(Get-Command $flutterExe -ErrorAction SilentlyContinue)) {
  if (Test-Path 'E:\Development\src\flutter\bin\flutter.bat') {
    $flutterExe = 'E:\Development\src\flutter\bin\flutter.bat'
  } elseif (Test-Path 'D:\Development\src\flutter\bin\flutter.bat') {
    $flutterExe = 'D:\Development\src\flutter\bin\flutter.bat'
  }
}

if ($Rebuild -or !(Test-Path (Join-Path $projectRoot 'mobile\build\web\main.dart.js'))) {
  Write-Output 'Building Flutter web...'
  Push-Location (Join-Path $projectRoot 'mobile')
  try {
    & $flutterExe build web --debug --no-pub --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:3001
    if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed.' }
  } finally { Pop-Location }
}

# 4. Start backend and frontend services
foreach ($service in @(
  @{Port=3001; Script='dist\index.js'; Log='backend'},
  @{Port=8081; Script='scripts\serve-local-web.cjs'; Log='frontend'}
)) {
  $existing = Get-NetTCPConnection -LocalPort $service.Port -State Listen -ErrorAction SilentlyContinue
  if (!$existing) {
    $process = Start-Process -FilePath 'node.exe' -ArgumentList $service.Script -WorkingDirectory (Join-Path $projectRoot 'backend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $localDir "$($service.Log).log") -RedirectStandardError (Join-Path $localDir "$($service.Log).error.log")
    $process.Id | Set-Content (Join-Path $localDir "$($service.Log).pid")
    Write-Output "Started $($service.Log) on port $($service.Port) (PID: $($process.Id))"
  } else {
    Write-Output "$($service.Log) is already running on port $($service.Port)"
  }
}

Write-Output ''
Write-Output '========================================='
Write-Output ' The Thrive Salon is RUNNING LOCALLY'
Write-Output '========================================='
Write-Output 'Frontend App:   http://localhost:8081'
Write-Output 'Backend API:    http://127.0.0.1:3001'
Write-Output 'Database (pgAdmin): 127.0.0.1:5432 / thrive_local (User: postgres, Pass: admin123)'
Write-Output 'Owner Login:    owner@local.test / LocalSalon123!'
Write-Output 'Admin Login:    admin@local.test / LocalSalon123!'
Write-Output '========================================='
