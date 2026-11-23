# 定向重启 Metis Web + Solid Queue + 企微桥接（不动 PostgreSQL）
# 用于代码 / .env 变更后生效。start-dev.ps1 / stop-dev.ps1 的子集。

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

# 1. 停 Web（pid 文件）
$pidFile = Join-Path $PSScriptRoot "tmp\pids\server.pid"
if (Test-Path $pidFile) {
  $serverPid = [int](Get-Content $pidFile).Trim()
  Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  Write-Host "Web 已停止 (pid $serverPid)"
}

# 2. 停任务队列
Get-CimInstance Win32_Process -Filter "Name='ruby.exe'" |
  Where-Object { $_.CommandLine -match 'bin[\\/]jobs' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "任务队列已停止 (pid $($_.ProcessId))" }

# 3. 停企微桥接
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match 'wecom-bridge' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "企微桥接已停止 (pid $($_.ProcessId))" }

Start-Sleep -Seconds 2

# 4. 加载 .env（子进程继承）
Get-Content .env -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $i = $_.IndexOf('=')
  $k = $_.Substring(0, $i).Trim()
  $v = $_.Substring($i + 1).Trim()
  if ($v) { Set-Item "env:$k" $v }
}
$env:DATABASE_URL = "postgres://metis@127.0.0.1:5432/metis_development"

# 日志按日归档目录（stdout 重定向按启动日归档；Rails 日志由应用内
# DatedLogDevice 按写入日归档，见 lib/dated_log_device.rb）
$logDir = Join-Path $PSScriptRoot "log\$(Get-Date -Format yyyy-MM-dd)"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# 5. 起企微桥接
if ($env:WECOM_BOT_ID -and (Test-Path "clients/wecom-bridge/node_modules")) {
  Start-Process cmd -ArgumentList '/c',"node clients\wecom-bridge\index.js 1> $logDir\wecom-bridge.log 2> $logDir\wecom-bridge.err.log" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
  Write-Host "企微桥接已启动"
}

# 6. 起 Web
Start-Process cmd -ArgumentList '/c',"ruby bin\rails server -b 0.0.0.0 -p 3002 1> $logDir\rails-server.log 2> $logDir\rails-server.err.log" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
Write-Host "Web 已启动"

# 7. 起任务队列（Windows 无线程 fork，必须 --mode=async）
Start-Process cmd -ArgumentList '/c',"ruby bin\jobs --mode=async 1> $logDir\solid-queue.log 2> $logDir\solid-queue.err.log" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
Write-Host "任务队列已启动"
