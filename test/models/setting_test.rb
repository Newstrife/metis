require "test_helper"

class SettingTest < ActiveSupport::TestCase
  teardown { Setting.delete_all }

  test "unset keys fall back to the registry default" do
    assert_equal true, Setting.get("wecom.auto_provision")
    assert_equal [], Setting.get("wecom.group_whitelist")
  end

  test "set casts and persists; get reads it back" do
    Setting.set("wecom.group_whitelist", [ "wrA", " wrB ", "", "wrA" ])
    assert_equal %w[wrA wrB], Setting.get("wecom.group_whitelist")

    Setting.set("security.approval_push", "false")
    assert_equal false, Setting.get("security.approval_push")
  end

  test "unknown keys raise" do
    assert_raises(KeyError) { Setting.get("nope.nope") }
  end
end
