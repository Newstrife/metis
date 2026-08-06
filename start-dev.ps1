# Metis 本地开发环境一键启动（无需 Docker）
# 用法：在 PowerShell 中运行  .\start-dev.ps1
# 停止：在窗口里按 Ctrl+C；数据库可用 stop-dev.ps1 关闭

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 1. 启动 PostgreSQL（已在运行则跳过）
& E:\pi\pgsql\bin\pg_isready.exe -h 127.0.0.1 -p 5432 -q | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "启动 PostgreSQL ..."
  & E:\pi\pgsql\bin\pg_ctl.exe -D E:\pi\pgsql-data -l E:\pi\pgsql-data\server.log start | Out-Null
}

# 2. 加载 .env 里的 API key 等配置
Get-Content .env -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $i = $_.IndexOf('=')
  $k = $_.Substring(0, $i).Trim()
  $v = $_.Substring($i + 1).Trim()
  if ($v) { Set-Item "env:$k" $v }
}
$env:DATABASE_URL = "postgres://metis@127.0.0.1:5432/metis_development"

# 3. 启动 Web 服务（端口 3002）
# 企业微信桥接（已填 WECOM_BOT_ID 且依赖已装时随 dev 一起拉起）
if ($env:WECOM_BOT_ID -and (Test-Path "clients/wecom-bridge/node_modules")) {
  Write-Host "启动企业微信桥接 ..."
  Start-Process node -ArgumentList "clients/wecom-bridge/index.js" -WorkingDirectory $PSScriptRoot
}
Write-Host "Metis 启动中: http://localhost:3002  (登录: admin@metis.local / password)"
ruby bin/rails server
