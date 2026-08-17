require "test_helper"

class Settings::UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "admin@example.com", password: "password123", superuser: true)
    @member = User.create!(email: "member@example.com", password: "password123")
  end

  test "superuser sees the user list" do
    sign_in @admin
    get users_path
    assert_response :success
    assert_select ".member-name", /member@example\.com/
  end

  test "non-superuser is turned away" do
    sign_in @member
    get users_path
    assert_redirected_to models_path
  end

  test "superuser resets another user's password" do
    sign_in @admin
    patch user_path(@member), params: { user: { password: "newpass456" } }
    assert_redirected_to users_path
    assert @member.reload.valid_password?("newpass456")
  end

  test "reset with a blank password fails validation" do
    sign_in @admin
    patch user_path(@member), params: { user: { password: "" } }
    assert @member.reload.valid_password?("password123"), "原密码不应被覆盖"
  end

  test "superuser deletes a user along with their personal team" do
    sign_in @admin
    personal_team_id = @member.personal_team.id
    assert_difference "User.count", -1 do
      delete user_path(@member)
    end
    assert_nil Team.find_by(id: personal_team_id)
  end

  test "superuser cannot delete themselves" do
    sign_in @admin
    assert_no_difference "User.count" do
      delete user_path(@admin)
    end
  end
end
