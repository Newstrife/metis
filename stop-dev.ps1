# 停止 Metis 本地开发环境（Web 服务 + PostgreSQL）

# 1. 停 Web 服务（按 pid 文件）
$pidFile = Join-Path $PSScriptRoot "tmp\pids\server.pid"
if (Test-Path $pidFile) {
  $serverPid = [int](Get-Content $pidFile).Trim()
  Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  Write-Host "Web 服务已停止 (pid $serverPid)"
} else {
  Write-Host "Web 服务未在运行"
}

# 2. 停 PostgreSQL
& E:\pi\pgsql\bin\pg_ctl.exe -D E:\pi\pgsql-data stop
