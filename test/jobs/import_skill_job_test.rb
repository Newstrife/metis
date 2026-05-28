require "test_helper"

class ImportSkillJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "j-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @team = @user.personal_team
  end

  test "delegates to SkillImporter with the resolved team and user" do
    captured = {}
    with_stub(Agent::SkillImporter, :from_github, ->(url:, team:, by:) {
      captured.merge!(url: url, team: team, by: by)
      Skill.new
    }) do
      ImportSkillJob.perform_now(team_id: @team.id, by_user_id: @user.id, url: "owner/repo")
    end

    assert_equal "owner/repo", captured[:url]
    assert_equal @team, captured[:team]
    assert_equal @user, captured[:by]
  end

  test "swallows importer errors and logs a warning" do
    with_stub(Agent::SkillImporter, :from_github, ->(**) { raise Agent::SkillImporter::Error, "boom" }) do
      assert_nothing_raised do
        ImportSkillJob.perform_now(team_id: @team.id, by_user_id: @user.id, url: "owner/repo")
      end
    end
  end
end
