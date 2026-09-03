require "test_helper"

class DataDirectoryTest < ActiveSupport::TestCase
  test "rejects absolute paths" do
    dir = DataDirectory.new(name: "逃逸", path: 'E:\other\secret')
    assert_not dir.valid?
    assert dir.errors[:path].any?
  end

  test "rejects parent traversal" do
    dir = DataDirectory.new(name: "逃逸", path: "../secret")
    assert_not dir.valid?
  end

  test "accepts a plain relative subdirectory" do
    dir = DataDirectory.new(name: "考勤", path: "测试目录甲")
    assert dir.valid?
  end

  test "paths are unique" do
    DataDirectory.create!(name: "考勤", path: "测试目录甲")
    dup = DataDirectory.new(name: "考勤2", path: "测试目录甲")
    assert_not dup.valid?
  end
end
