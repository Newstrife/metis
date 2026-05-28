require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "proj-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  def team = @user.personal_team

  test "index renders the empty-state copy when the team has no projects" do
    get projects_path
    assert_response :success
    assert_select ".pane-empty", text: /No projects yet/
  end

  test "index lists the team's projects with their external-ref chips" do
    team.projects.create!(name: "Metis", external_refs: { "github" => { "repo" => "chagel/metis" } })
    team.projects.create!(name: "Themis", external_refs: { "linear" => { "project_id" => "abc" } })

    get projects_path
    assert_response :success
    assert_select ".conn-name", text: "Metis"
    assert_select ".conn-name", text: "Themis"
    assert_select ".tag", text: "chagel/metis"
    assert_select ".tag", text: "Linear"
  end

  test "create persists name + about and stamps created_by / updated_by" do
    assert_difference -> { team.projects.count }, 1 do
      post projects_path, params: { project: { name: "Metis", about: "Rails 8.1 chat over pi." } }
    end
    project = team.projects.find_by!(name: "Metis")
    assert_equal "Rails 8.1 chat over pi.", project.about
    assert_equal @user.id, project.created_by_id
    assert_equal @user.id, project.updated_by_id
    assert_redirected_to edit_project_path(project)
  end

  test "create with a blank name re-renders the new form" do
    post projects_path, params: { project: { name: "" } }
    assert_response :unprocessable_entity
    assert_select ".flash.error"
  end

  test "update accepts permitted external_refs and stores the sparse map" do
    project = team.projects.create!(name: "Metis")
    patch project_path(project), params: {
      project: {
        about: "edited",
        external_refs: { github: { repo: "chagel/metis" }, linear: { project_id: "p-7" } }
      }
    }
    project.reload
    assert_equal "edited", project.about
    assert_equal "chagel/metis", project.github_repo
    assert_equal "p-7", project.linear_project_id
  end

  test "update drops connector keys whose values are blank — sparse external_refs is a feature, not an empty hash" do
    project = team.projects.create!(name: "Metis",
                                     external_refs: { "github" => { "repo" => "chagel/metis" } })
    patch project_path(project), params: {
      project: { external_refs: { github: { repo: "" }, linear: { project_id: "p-7" } } }
    }
    project.reload
    refute project.external_refs.key?("github"), "blank fields must not write an empty connector key"
    assert_equal "p-7", project.linear_project_id
  end

  test "update rejects arbitrary nested keys not in the permitted external_refs schema" do
    project = team.projects.create!(name: "Metis")
    patch project_path(project), params: {
      project: { external_refs: { github: { repo: "chagel/metis", malicious: "yes" },
                                   notion: { workspace_id: "w-1" } } }
    }
    project.reload
    assert_equal({ "repo" => "chagel/metis" }, project.external_refs["github"])
    refute project.external_refs.key?("notion")
  end

  test "destroy deletes the project and detaches (does not destroy) its conversations" do
    project = team.projects.create!(name: "Metis")
    conversation = @user.conversations.create!(project: project)

    assert_difference -> { team.projects.count }, -1 do
      assert_no_difference -> { @user.conversations.count } do
        delete project_path(project)
      end
    end
    assert_nil conversation.reload.project_id
    assert_redirected_to projects_path
  end

  test "another team's project is not accessible" do
    other = Team.create!(name: "Other")
    foreign = other.projects.create!(name: "Secret")
    get edit_project_path(foreign)
    assert_response :not_found
  end
end
