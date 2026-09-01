# restart wecom-bridge only (leave puma / solid-queue / PG untouched)
$ErrorActionPreference = "Stop"
Set-Location E:\pi\metis

# 1. load .env (same logic as start-dev.ps1)
Get-Content .env -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $i = $_.IndexOf('=')
  $k = $_.Substring(0, $i).Trim()
  $v = $_.Substring($i + 1).Trim()
  if ($v) { Set-Item "env:$k" $v }
}

# 2. kill zombie bridge (match command line to avoid killing other node.exe)
$bridge = Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -like '*wecom-bridge*' }
if ($bridge) {
  $bridge | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "killed old bridge PID $($_.ProcessId)" }
} else {
  Write-Host "no running bridge found"
}

Start-Sleep -Seconds 1

# 3. start fresh bridge (same as start-dev.ps1: hidden window + log redirect)
Start-Process cmd -ArgumentList '/c','node clients\wecom-bridge\index.js 1> log\wecom-bridge.log 2> log\wecom-bridge.err.log' -WorkingDirectory "E:\pi\metis" -WindowStyle Hidden
Write-Host "new bridge started"
