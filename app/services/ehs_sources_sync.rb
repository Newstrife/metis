# Syncs the UI-edited EHS watchlist (Setting "ehs.sources", one
# "名称 | URL" per line) back to the monitor's sources.json.
#
# The Setting is the source of truth for **membership and names**;
# tuned parser fields (item_pattern/date groups) of URLs already in the
# file are preserved untouched; brand-new URLs get `item_pattern:
# "generic"` so a non-technical edit works without writing regex.
# monitor.js reads only this file — it never talks to Rails.
class EhsSourcesSync
  DEFAULT_PATH = "E:/pi/ehs-monitor/sources.json".freeze

  def self.call
    new.call
  end

  def call
    entries = parse_lines(Setting.get("ehs.sources"))
    existing = load_existing

    merged = entries.filter_map do |name, url|
      next unless url.match?(%r{\Ahttps?://})

      if (old = existing[url])
        old.merge("name" => name) # 保留调好的解析字段，只更新名称
      else
        generic_entry(name, url)
      end
    end

    atomic_write(merged)
    merged.size
  end

  private

  def path
    ENV["EHS_MONITOR_SOURCES"].presence || DEFAULT_PATH
  end

  def parse_lines(lines)
    Array(lines).map do |line|
      name, url = line.to_s.split("|", 2).map(&:strip)
      [ name.presence || url.to_s, url.to_s ]
    end
  end

  def load_existing
    return {} unless File.exist?(path)

    JSON.parse(File.read(path, encoding: "UTF-8")).index_by { |s| s["list_url"] }
  rescue JSON::ParserError
    {} # 文件损坏时按全新处理——既有 tuned 配置丢失比静默写坏强，日志里会留痕
  end

  def generic_entry(name, url)
    uri = URI.parse(url)
    {
      "name" => name,
      "list_url" => url,
      "base_url" => "#{uri.scheme}://#{uri.host}",
      "item_pattern" => "generic",
      "js_rendered" => false
    }
  end

  def atomic_write(data)
    tmp = "#{path}.tmp"
    File.write(tmp, JSON.pretty_generate(data) + "\n", encoding: "UTF-8")
    FileUtils.mv(tmp, path, force: true)
  end
end
