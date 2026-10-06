param([switch]$Rebuild)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$env:NODE_ENV = 'development'
$pgCtl = 'C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe'
$pgData = Join-Path $projectRoot '.local\postgres'
if (!(Test-Path (Join-Path $pgData 'PG_VERSION'))) { throw 'Local database has not been initialized.' }
& $pgCtl -D $pgData status *> $null
if ($LASTEXITCODE -ne 0) {
  & $pgCtl -D $pgData -l (Join-Path $projectRoot '.local\postgres.log') start
  if ($LASTEXITCODE -ne 0) { throw 'Could not start project PostgreSQL.' }
}
if ($Rebuild -or !(Test-Path (Join-Path $projectRoot 'backend\dist\index.js'))) {
  & npm.cmd run build --prefix (Join-Path $projectRoot 'backend')
  if ($LASTEXITCODE -ne 0) { throw 'Backend build failed.' }
}
if ($Rebuild -or !(Test-Path (Join-Path $projectRoot 'mobile\build\web\main.dart.js'))) {
  Push-Location (Join-Path $projectRoot 'mobile')
  try {
    & flutter.bat build web --debug --no-pub --no-wasm-dry-run --dart-define=API_BASE_URL=http://127.0.0.1:3001
    if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed.' }
  } finally { Pop-Location }
}
foreach ($service in @(
  @{Port=3001; Script='dist\index.js'; Log='backend'},
  @{Port=8081; Script='scripts\serve-local-web.cjs'; Log='frontend'}
)) {
  $existing = Get-NetTCPConnection -LocalPort $service.Port -State Listen -ErrorAction SilentlyContinue
  if (!$existing) {
    $process = Start-Process -FilePath 'node.exe' -ArgumentList $service.Script -WorkingDirectory (Join-Path $projectRoot 'backend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $projectRoot ".local\$($service.Log).log") -RedirectStandardError (Join-Path $projectRoot ".local\$($service.Log).error.log")
    $process.Id | Set-Content (Join-Path $projectRoot ".local\$($service.Log).pid")
  }
}
Write-Output 'App: http://localhost:8081'
Write-Output 'Local login: owner@local.test / LocalSalon123!'
Write-Output 'Database: 127.0.0.1:55433/thrive_local (isolated project instance)'
