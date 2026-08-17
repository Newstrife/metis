# 停止 Metis 本地开发环境（Web 服务 + 企微桥接 + PostgreSQL）

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

# 2. 停企业微信桥接（命令行含 wecom-bridge 的 node 进程）
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match 'wecom-bridge' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "企微桥接已停止 (pid $($_.ProcessId))" }

# 3. 停 PostgreSQL
& E:\pi\pgsql\bin\pg_ctl.exe -D E:\pi\pgsql-data stop
