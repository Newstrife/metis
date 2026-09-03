require "test_helper"

class Settings::DataDirectoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "admin@example.com", password: "password123", superuser: true)
    @member = User.create!(email: "member@example.com", password: "password123")
  end

  test "superuser sees the directory list" do
    sign_in @admin
    get data_directories_path
    assert_response :success
  end

  test "superuser registers a directory" do
    sign_in @admin
    assert_difference("DataDirectory.count") do
      post data_directories_path, params: { data_directory: { name: "考勤", path: "测试目录丙", public_access: "1" } }
    end
    assert DataDirectory.find_by(path: "测试目录丙").public_access?
  end

  test "rejects escaping paths" do
    sign_in @admin
    assert_no_difference("DataDirectory.count") do
      post data_directories_path, params: { data_directory: { name: "逃逸", path: "../outside" } }
    end
  end

  test "non-superuser is turned away" do
    sign_in @member
    get data_directories_path
    assert_redirected_to models_path
  end
end
