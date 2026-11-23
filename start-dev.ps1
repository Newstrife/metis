# Metis 本地开发环境一键启动（无需 Docker）
# 用法：在 PowerShell 中运行  .\start-dev.ps1
# 停止：.\stop-dev.ps1（Web + 企微桥接 + PostgreSQL）
#
# 设计：postgres / rails / 桥接都在各自独立的隐藏窗口里运行，本脚本点火即退。
# 不要图省事把服务跑在本窗口前台——关掉窗口等于 Ctrl+C，会把整个控制台
# 进程组（含 postgres 后端）一起杀掉。

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 0. 日志超限就地截断（保留尾部 50MB，阈值内自动跳过；见 truncate-dev-logs.ps1）
& powershell -ExecutionPolicy Bypass -NoProfile -File "$PSScriptRoot\truncate-dev-logs.ps1"

# 0.5 日志按日归档目录。Rails 日志由应用内 DatedLogDevice 按写入日写入
# log/<日期>/development.log（见 lib/dated_log_device.rb）；这里的 stdout
# 重定向按【启动日】归档——进程跨天后仍留在启动日目录，重启后进新目录。
$logDir = Join-Path $PSScriptRoot "log\$(Get-Date -Format yyyy-MM-dd)"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

# 1. 启动 PostgreSQL（已在运行则跳过；独立隐藏窗口，脱离本控制台）
& E:\pi\pgsql\bin\pg_isready.exe -h 127.0.0.1 -p 5432 -q | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "启动 PostgreSQL ..."
  # cmd /c 同步等 pg_ctl 退出（pg_ctl -w 自带就绪等待）；不能用 PowerShell 管道
  #（等 stdout EOF 会卡死）或 Start-Process -Wait（会等 postgres 后代，永不返回）
  cmd /c "E:\pi\pgsql\bin\pg_ctl.exe -D E:\pi\pgsql-data -l E:\pi\pgsql-data\server.log -w start >NUL 2>&1"
}

# 2. 加载 .env 里的 API key 等配置（子进程继承本进程环境）
Get-Content .env -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $i = $_.IndexOf('=')
  $k = $_.Substring(0, $i).Trim()
  $v = $_.Substring($i + 1).Trim()
  if ($v) { Set-Item "env:$k" $v }
}
$env:DATABASE_URL = "postgres://metis@127.0.0.1:5432/metis_development"

# 3. 已在运行则直接退出，避免端口冲突
if (Get-NetTCPConnection -LocalPort 3002 -State Listen -ErrorAction SilentlyContinue) {
  Write-Host "Metis 已在运行，直接打开 http://localhost:3002 即可"
  exit 0
}
# 清理上次异常退出残留的 server.pid（进程已不在而文件还在）
$pidFile = "tmp/pids/server.pid"
if (Test-Path $pidFile) {
  Remove-Item $pidFile -Force
  Write-Host "已清理残留的 server.pid"
}

# 3.5 防火墙放行 3002（局域网访问需要；需管理员权限，非管理员则提示一次后跳过）
if (-not (Get-NetFirewallRule -DisplayName "Metis Web 3002" -ErrorAction SilentlyContinue)) {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($isAdmin) {
    New-NetFirewallRule -DisplayName "Metis Web 3002" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3002 | Out-Null
    Write-Host "已添加防火墙入站规则: Metis Web 3002"
  } else {
    Write-Host "提示: 局域网访问需管理员运行一次: netsh advfirewall firewall add rule name=`"Metis Web 3002`" dir=in action=allow protocol=TCP localport=3002"
  }
}

# 4. 企业微信桥接（已填 WECOM_BOT_ID 且依赖已装时随 dev 一起拉起）
# 用 cmd /c 做重定向：Start-Process -Redirect* 会踩文件锁/句柄继承的坑
if ($env:WECOM_BOT_ID -and (Test-Path "clients/wecom-bridge/node_modules")) {
  Write-Host "启动企业微信桥接 ..."
  Start-Process cmd -ArgumentList '/c',"node clients\wecom-bridge\index.js 1> $logDir\wecom-bridge.log 2> $logDir\wecom-bridge.err.log" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
}

# 5. Web 服务（端口 3002，绑定 0.0.0.0 允许局域网访问，独立隐藏窗口 + 日志文件）
Write-Host "Metis 启动中: http://localhost:3002  局域网: http://10.1.20.3:3002  (登录: admin@metis.local / password)"
Start-Process cmd -ArgumentList '/c',"ruby bin\rails server -b 0.0.0.0 -p 3002 1> $logDir\rails-server.log 2> $logDir\rails-server.err.log" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden

# 6. 后台任务 supervisor（Solid Queue：ChatJob、定时 Routine 等都靠它）
# Windows 没有 fork()，必须用 --mode=async（线程模式）
Start-Process cmd -ArgumentList '/c',"ruby bin\jobs --mode=async 1> $logDir\solid-queue.log 2> $logDir\solid-queue.err.log" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
Write-Host "已全部在后台启动，日志见 log\rails-server.log；停止用 .\stop-dev.ps1"
