require "test_helper"

class Settings::RolesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "admin@example.com", password: "password123", superuser: true)
    @member = User.create!(email: "member@example.com", password: "password123")
    @dir = DataDirectory.create!(name: "名册", path: "测试目录乙")
  end

  test "superuser manages roles" do
    sign_in @admin
    get roles_path
    assert_response :success
  end

  test "non-superuser is turned away" do
    sign_in @member
    get roles_path
    assert_redirected_to models_path
  end

  test "superuser creates a role with directory grants" do
    sign_in @admin
    assert_difference("Role.count") do
      post roles_path, params: { role: { name: "人事", data_directory_ids: [ @dir.id ] } }
    end
    assert_includes Role.find_by(name: "人事").data_directories, @dir
  end

  test "superuser updates a role's grants" do
    sign_in @admin
    role = Role.create!(name: "生产")
    patch role_path(role), params: { role: { name: "生产", data_directory_ids: [ @dir.id ] } }
    assert_includes role.reload.data_directories, @dir
  end
end
