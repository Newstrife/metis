# Metis 日志维护：① 清理超过保留期的日期目录（兜底）② 平铺旧日志超限就地截断
# 用法：powershell -ExecutionPolicy Bypass -File truncate-dev-logs.ps1
# 由每日计划任务 "MetisLogTruncate" 和 start-dev.ps1 调用；无东西可清时秒过。
#
# ① 日期目录清理：应用内 DatedLogDevice 跨天时会自清理（保留期默认 7 天，
#   METIS_LOG_RETENTION_DAYS 可覆盖），本脚本做兜底——覆盖 stdout 重定向目录
#   （按启动日归档、进程不重启就一直写）和残留目录。删除当天活跃目录不会发生
#   （目录名与截止日比较天然排除）；正在被进程写入的旧目录删除会部分失败，
#   残留文件留待下次。SilentlyContinue。
#
# ② 平铺旧日志截断（遗留兼容，新架构下平铺日志不再增长）：以【共享读写】方式
#   打开，append 句柄不受影响，无需停服务；Windows 无法重命名打开中的文件，
#   所以就地截断是唯一免停机方案，截断瞬间并发写入最多丢一两行日志，可接受。

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

# ---- ① 清理过期日期目录 ----
$retentionDays = if ($env:METIS_LOG_RETENTION_DAYS) { [int]$env:METIS_LOG_RETENTION_DAYS } else { 7 }
$cutoff = (Get-Date).AddDays(-$retentionDays).ToString("yyyy-MM-dd")
Get-ChildItem -Path (Join-Path $PSScriptRoot "log") -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -lt $cutoff } |
  ForEach-Object {
    Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue
    Write-Host ("{0}: 已清理（超过 {1} 天保留期）" -f $_.Name, $retentionDays)
  }

# ---- ② 平铺旧日志超限截断（遗留兼容）----

$KeepMB = 50    # 截断后保留的最后 N MB
$MaxMB  = 200   # 超过此大小才截断，否则跳过
$Logs   = @(
  "log\development.log",
  "log\rails-server.log",
  "log\solid-queue.log",
  "log\wecom-bridge.log",
  "log\test.log",
  "log\dev.log"
)

foreach ($rel in $Logs) {
  $path = Join-Path $PSScriptRoot $rel
  if (-not (Test-Path $path)) { continue }
  $len = (Get-Item $path -ErrorAction SilentlyContinue).Length
  if ($null -eq $len -or $len -le ($MaxMB * 1MB)) { continue }

  try {
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite)
    try {
      $tailLen = $KeepMB * 1MB
      if ($fs.Length -lt $tailLen) { $tailLen = $fs.Length }
      $fs.Seek(-$tailLen, [System.IO.SeekOrigin]::End) | Out-Null
      $tail = New-Object byte[] $tailLen
      $read = 0
      while ($read -lt $tailLen) {
        $n = $fs.Read($tail, $read, $tailLen - $read)
        if ($n -le 0) { break }
        $read += $n
      }
      $fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
      $fs.Write($tail, 0, $read)
      $fs.SetLength($read)
      Write-Host ("{0}: {1:N0} MB -> {2:N1} MB" -f $rel, ($len / 1MB), ($read / 1MB))
    } finally { $fs.Close() }
  } catch {
    Write-Host ("{0}: 截断失败: {1}" -f $rel, $_.Exception.Message)
  }
}
