require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "sk-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  def team = @user.personal_team

  def make_skill(**attrs)
    team.skills.create!({ slug: "summarize", description: "Summarize" }.merge(attrs))
  end

  test "index lists the team's skills" do
    make_skill
    get skills_path
    assert_response :success
    assert_select ".conn-list .conn-name", text: "summarize"
  end

  test "index empty state" do
    get skills_path
    assert_response :success
    assert_select ".pane-empty"
  end

  test "edit renders SKILL.md in the textarea" do
    skill = make_skill
    skill.replace_skill_md!("# Hello")
    skill.save!
    get edit_skill_path(skill)
    assert_response :success
    assert_select "textarea#skill_skill_md", text: /# Hello/
  end

  test "create writes the skill_md textarea through replace_skill_md!" do
    assert_difference -> { team.skills.count }, 1 do
      post skills_path, params: {
        skill: { slug: "summarize", description: "x", enabled: "1", skill_md: "# top" }
      }
    end
    skill = team.skills.find_by!(slug: "summarize")
    assert_redirected_to edit_skill_path(skill)
    assert_equal "# top", skill.content_cache
    assert_equal current_user_id, skill.created_by_id
  end

  test "create with invalid slug re-renders the form" do
    post skills_path, params: { skill: { slug: "Bad Slug", description: "x" } }
    assert_response :unprocessable_entity
    assert_select ".flash.error"
  end

  test "update edits an existing skill" do
    skill = make_skill
    patch skill_path(skill), params: { skill: { description: "Updated", skill_md: "# new" } }
    skill.reload
    assert_equal "Updated", skill.description
    assert_equal "# new", skill.content_cache
  end

  test "destroy deletes the skill" do
    skill = make_skill
    assert_difference -> { team.skills.count }, -1 do
      delete skill_path(skill)
    end
    assert_redirected_to skills_path
  end

  test "another team's skills are not accessible" do
    other = Team.create!(name: "Other")
    foreign = other.skills.create!(slug: "secret", description: "x")
    get edit_skill_path(foreign)
    assert_response :not_found
  end

  private

  def current_user_id = @user.id
end
