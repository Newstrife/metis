# frozen_string_literal: true

# 按日分目录的日志设备：log/2026-11-23/development.log。
#
# 为什么不用 Logger.new(path, "daily") / config.log_file_size：Windows 无法
# 重命名打开中的文件，而 Web（puma）与 worker（bin/jobs）两个进程共享同一
# 日志文件，内置轮转必然有进程输掉重命名竞态（2026-08-28 事故：日志流死亡，
# 4 天刷出 45 万行 "log writing failed"）。本设备从不重命名——每个进程在
# 跨天后的首次写入时各自切换到新文件；旧文件从此无人打开，保留期清理只需
# 整目录删除，对 Windows 与多进程都天然安全。
#
# 用法：当作 Logger 的 logdev 传入 —— ActiveSupport::Logger.new(DatedLogDevice.new(...))。
# 实现 Logger::LogDevice 的最小接口（write / close / flush / reopen）；
# Ruby Logger 会用 LogDevice 的互斥锁包裹 write，跨天切换因此是线程安全的。
class DatedLogDevice
  def initialize(dir, name:, retention_days: nil)
    require "fileutils"
    require "date"
    @dir = Pathname.new(dir)
    @name = name
    @retention_days = retention_days
    @io = nil
    @date = nil
  end

  # LogDevice 接口 -----------------------------------------------------------

  def write(message)
    ensure_today_file
    @io.write(message)
  end

  def close
    @io&.close
    @io = nil
    @date = nil
  end

  def flush
    @io&.flush
  end

  def reopen(_logdev = nil)
    close
    ensure_today_file
    self
  end

  private

  def ensure_today_file
    today = Date.today
    return if @date == today && @io

    @io&.close
    @date = today
    path = @dir.join(today.iso8601, @name)
    FileUtils.mkdir_p(path.dirname)
    @io = File.open(path, "a")
    @io.sync = true
    prune_old_folders(today)
  end

  # 跨天时顺带清理超过保留期的日期目录（ISO 日期名可直接按字符串比较）。
  # 此刻旧目录里已无进程持有打开的文件；删除失败（如偶发占用）留待次日重试。
  def prune_old_folders(today)
    return unless @retention_days.is_a?(Integer) && @retention_days.positive?

    cutoff = (today - @retention_days).iso8601
    Dir.children(@dir).each do |entry|
      next unless entry.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      next if entry >= cutoff

      FileUtils.rm_rf(@dir.join(entry))
    rescue StandardError => e
      warn "DatedLogDevice: 清理日志目录 #{entry} 失败: #{e.message}"
    end
  end
end
