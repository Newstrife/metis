require "test_helper"
require "json"
require "tmpdir"

class EhsSourcesSyncTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "sources.json")
    File.write(@path, "", encoding: "UTF-8")
    @old_env = ENV["EHS_MONITOR_SOURCES"]
    ENV["EHS_MONITOR_SOURCES"] = @path
    @old_setting = Setting.get("ehs.sources")
  end

  teardown do
    ENV["EHS_MONITOR_SOURCES"] = @old_env
    Setting.set("ehs.sources", @old_setting)
    FileUtils.remove_entry(@dir)
  end

  def read_json
    JSON.parse(File.read(@path, encoding: "UTF-8"))
  end

  test "new URL gets the generic parser entry" do
    Setting.set("ehs.sources", [ "测试源 | https://example.gov.cn/list" ])
    EhsSourcesSync.call

    (entry,) = read_json
    assert_equal "测试源", entry["name"]
    assert_equal "generic", entry["item_pattern"]
    assert_equal "https://example.gov.cn", entry["base_url"]
    assert_equal false, entry["js_rendered"]
  end

  test "existing URL keeps its tuned parser fields, name updates" do
    tuned = [ { "name" => "旧名", "list_url" => "https://mem.gov.cn/a",
                "item_pattern" => "<a>(.*)</a>", "group_title" => 1, "js_rendered" => false } ]
    File.write(@path, JSON.generate(tuned), encoding: "UTF-8")

    Setting.set("ehs.sources", [ "新名字 | https://mem.gov.cn/a" ])
    EhsSourcesSync.call

    (entry,) = read_json
    assert_equal "新名字", entry["name"]
    assert_equal "<a>(.*)</a>", entry["item_pattern"]
    assert_equal 1, entry["group_title"]
  end

  test "removing a line stops watching that source" do
    File.write(@path, JSON.generate([ { "name" => "甲", "list_url" => "https://a.gov.cn" },
                                      { "name" => "乙", "list_url" => "https://b.gov.cn" } ]), encoding: "UTF-8")
    Setting.set("ehs.sources", [ "甲 | https://a.gov.cn" ])
    EhsSourcesSync.call

    assert_equal [ "https://a.gov.cn" ], read_json.map { |e| e["list_url"] }
  end

  test "lines without a URL are skipped" do
    Setting.set("ehs.sources", [ "没有竖线", "只有名字 | ", "好 | https://ok.gov.cn" ])
    EhsSourcesSync.call

    assert_equal [ "https://ok.gov.cn" ], read_json.map { |e| e["list_url"] }
  end
end
