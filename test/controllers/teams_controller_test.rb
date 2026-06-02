require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "owner@example.com", password: "password123")
    @other = Team.create!(name: "Acme")
    @user.memberships.create!(team: @other, role: :admin)
    sign_in @user
  end

  test "switching sets the active team and redirects back" do
    post switch_team_path(@other), headers: { "HTTP_REFERER" => root_path }
    assert_redirected_to root_path

    # The active team now scopes resources: a conversation in @other shows
    # in the sidebar, one in the personal team does not.
    @user.conversations.create!(team: @other, title: "Shared chat")
    @user.conversations.create!(team: @user.personal_team, title: "Solo chat")

    get conversations_path
    assert_select ".sidebar .convo .tt", text: "Shared chat"
    assert_select ".sidebar .convo .tt", text: "Solo chat", count: 0
  end

  test "cannot switch to a team the user is not a member of" do
    stranger_team = Team.create!(name: "Stranger")
    post switch_team_path(stranger_team)
    assert_response :not_found
  end

  test "defaults to the personal team when nothing is selected" do
    @user.conversations.create!(team: @user.personal_team, title: "Solo chat")
    get conversations_path
    assert_select ".sidebar .convo .tt", text: "Solo chat"
  end

  test "creating a team makes the user its owner and switches into it" do
    assert_difference -> { Team.count } => 1, -> { @user.memberships.count } => 1 do
      post teams_path, params: { team: { name: "Beta Squad" } }
    end

    team = Team.find_by!(name: "Beta Squad")
    assert_not team.personal?
    assert @user.memberships.find_by(team: team).owner?
    assert_redirected_to team_path
    follow_redirect!
    assert_select ".pane-title", text: "Team"
  end

  test "creating a team with a blank name re-renders the form" do
    assert_no_difference -> { Team.count } do
      post teams_path, params: { team: { name: "" } }
    end
    assert_response :unprocessable_entity
  end
end
