require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "proj-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  def team = @user.personal_team

  # ResourcePicker::Github / ::Linear are modules with `module_function`
  # methods, which Minitest's `stub` can't reach (it needs a class).
  # Swap the singleton method for the block's duration.
  def with_picker_stub(picker_module, return_value)
    original = picker_module.method(:list)
    picker_module.define_singleton_method(:list) { |**| return_value }
    yield
  ensure
    picker_module.define_singleton_method(:list, original)
  end

  # Provision a connector for the team + an OAuth grant for the user —
  # both must exist for the project edit page to surface that
  # provider's picker.
  def connect_provider(provider)
    team.connectors.create!(name: provider, transport: :http, catalog_key: provider,
                             definition: { "url" => "https://example/#{provider}" })
    @user.oauth_grants.create!(provider: provider, access_token: "token-#{provider}",
                                refresh_token: "rt", expires_at: 1.hour.from_now,
                                scopes: provider == "linear" ? "read write issues:create" : "repo read:user")
  end

  test "index renders the empty-state copy when the team has no projects" do
    get projects_path
    assert_response :success
    assert_select ".pane-empty", text: /No projects yet/
  end

  test "index lists the team's projects with their external-ref chips — display name when stored, value otherwise" do
    team.projects.create!(name: "Metis", external_refs: { "github" => { "repo" => "chagel/metis" } })
    # Linear stores both id (agent-facing) and project_name (human-facing).
    team.projects.create!(name: "Themis",
                           external_refs: { "linear" => { "project_id" => "abc", "project_name" => "Themis Linear" } })
    # Legacy: pre-display-field rows fall back to the id so the chip still shows something.
    team.projects.create!(name: "Legacy", external_refs: { "linear" => { "project_id" => "old-uuid" } })

    get projects_path
    assert_response :success
    assert_select ".conn-name", text: "Metis"
    assert_select ".tag", text: "chagel/metis"
    assert_select ".tag", text: "Themis Linear"
    assert_select ".tag", text: "old-uuid"
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
    assert_equal "chagel/metis", project.ref_for("github", "repo")
    assert_equal "p-7", project.ref_for("linear", "project_id")
  end

  test "update drops connector keys whose values are blank — sparse external_refs is a feature, not an empty hash" do
    project = team.projects.create!(name: "Metis",
                                     external_refs: { "github" => { "repo" => "chagel/metis" } })
    patch project_path(project), params: {
      project: { external_refs: { github: { repo: "" }, linear: { project_id: "p-7" } } }
    }
    project.reload
    refute project.external_refs.key?("github"), "blank fields must not write an empty connector key"
    assert_equal "p-7", project.ref_for("linear", "project_id")
  end

  test "update accepts the Linear display name field alongside the id and persists both — the placeholder shows the name, not the uuid" do
    project = team.projects.create!(name: "Metis")
    patch project_path(project), params: {
      project: {
        external_refs: { linear: { project_id: "abc-123", project_name: "Metis Linear" } }
      }
    }
    project.reload
    assert_equal "abc-123", project.ref_for("linear", "project_id")
    assert_equal "Metis Linear", project.ref_for("linear", "project_name")
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

  test "edit renders the form immediately and defers picker loading to a click — no src= on the frames, no outbound HTTP" do
    connect_provider("github")
    connect_provider("linear")
    project = team.projects.create!(name: "Metis")
    get edit_project_path(project)
    assert_response :success

    # Frames exist as targets but don't auto-fetch.
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"}:not([src])"
    assert_select "turbo-frame##{"project_#{project.id}_picker_linear"}:not([src])"

    # A select-shaped placeholder is the user's tap target inside each frame.
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"} a.ref-placeholder[href=?]",
                  picker_project_path(project, provider: "github")
    assert_select "turbo-frame##{"project_#{project.id}_picker_linear"} a.ref-placeholder[href=?]",
                  picker_project_path(project, provider: "linear")
    # Empty state shows a hint, not a value.
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"} .ref-placeholder-hint", text: /Select a repository/
    assert_select "turbo-frame##{"project_#{project.id}_picker_linear"} .ref-placeholder-hint", text: /Select a project/
  end

  test "edit shows the current external_refs values inside the placeholder without firing the picker" do
    connect_provider("github")
    connect_provider("linear")
    project = team.projects.create!(name: "Metis",
                                     external_refs: { "github" => { "repo" => "chagel/metis" },
                                                       "linear" => { "project_id" => "p-7" } })
    get edit_project_path(project)
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"} .ref-placeholder-value",
                  text: "chagel/metis"
    assert_select "turbo-frame##{"project_#{project.id}_picker_linear"} .ref-placeholder-value",
                  text: "p-7"
  end

  test "edit hides the entire External resources section when no connectors are authorized" do
    project = team.projects.create!(name: "Metis")
    get edit_project_path(project)
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"}", count: 0
    assert_select "turbo-frame##{"project_#{project.id}_picker_linear"}", count: 0
    assert_select "h2.form-section", text: "External resources", count: 0
  end

  test "edit shows only the connectors the user has authorized — Linear hidden when no Linear grant" do
    connect_provider("github")
    project = team.projects.create!(name: "Metis")
    get edit_project_path(project)
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"}"
    assert_select "turbo-frame##{"project_#{project.id}_picker_linear"}", count: 0
  end

  test "edit hides the picker when the team has an OAuth grant but the connector isn't installed for the team" do
    # Grant present, Connector record absent — installation gate filters out.
    @user.oauth_grants.create!(provider: "github", access_token: "t",
                                refresh_token: "r", expires_at: 1.hour.from_now,
                                scopes: "repo read:user")
    project = team.projects.create!(name: "Metis")
    get edit_project_path(project)
    assert_select "turbo-frame##{"project_#{project.id}_picker_github"}", count: 0
  end

  test "edit always emits the hidden inputs for external_refs so existing values survive a save when pickers are hidden" do
    project = team.projects.create!(name: "Metis",
                                     external_refs: { "github" => { "repo" => "chagel/metis" } })
    get edit_project_path(project)
    # No connectors authorized → no pickers, but the hidden input still rides on the form.
    assert_select "input[type=hidden][name=?][value=?]",
                  "project[external_refs][github][repo]", "chagel/metis"
  end

  test "new renders pickers when connectors are authorized — uses the collection picker route" do
    connect_provider("github")
    get new_project_path
    # Frame id keys on "new_" since the project isn't persisted yet.
    assert_select "turbo-frame#new_picker_github:not([src]) a.ref-placeholder[href=?]",
                  new_picker_projects_path(provider: "github")
  end

  test "new hides the entire External resources section when no connectors are authorized" do
    get new_project_path
    assert_response :success
    assert_select "turbo-frame#new_picker_github", count: 0
    assert_select "h2.form-section", text: "External resources", count: 0
  end

  test "create accepts external_refs picked on the new form and persists them in one shot" do
    connect_provider("github")
    assert_difference -> { team.projects.count }, 1 do
      post projects_path, params: {
        project: { name: "Metis",
                   external_refs: { github: { repo: "chagel/metis" } } }
      }
    end
    project = team.projects.find_by!(name: "Metis")
    assert_equal "chagel/metis", project.ref_for("github", "repo")
  end

  test "new_picker renders the github frame populated from ResourcePicker for an unpersisted project" do
    connect_provider("github")
    with_picker_stub(ResourcePicker::Github, [ { value: "chagel/metis", label: "chagel/metis" } ]) do
      get new_picker_projects_path(provider: "github")
    end
    assert_response :success
    assert_select "turbo-frame#new_picker_github"
    assert_select "select[name=?] option[value=?]",
                  "project[external_refs][github][repo]", "chagel/metis"
  end

  test "edit form carries hidden inputs for current external_refs so a save before picker frames load round-trips the values" do
    project = team.projects.create!(name: "Metis",
                                     external_refs: { "github" => { "repo" => "chagel/metis" },
                                                       "linear" => { "project_id" => "p-7" } })
    get edit_project_path(project)
    assert_select "input[type=hidden][name=?][value=?]",
                  "project[external_refs][github][repo]", "chagel/metis"
    assert_select "input[type=hidden][name=?][value=?]",
                  "project[external_refs][linear][project_id]", "p-7"
  end

  test "picker renders the github frame populated from ResourcePicker" do
    project = team.projects.create!(name: "Metis")
    with_picker_stub(ResourcePicker::Github, [ { value: "chagel/metis", label: "chagel/metis" } ]) do
      get picker_project_path(project, provider: "github")
    end
    assert_response :success
    assert_select "turbo-frame#project_#{project.id}_picker_github"
    assert_select "select[name=?] option[value=?]",
                  "project[external_refs][github][repo]", "chagel/metis"
  end

  test "picker renders the linear frame populated from ResourcePicker" do
    project = team.projects.create!(name: "Metis")
    with_picker_stub(ResourcePicker::Linear, [ { value: "p-7", label: "Metis" } ]) do
      get picker_project_path(project, provider: "linear")
    end
    assert_response :success
    assert_select "select[name=?] option[value=?]",
                  "project[external_refs][linear][project_id]", "p-7"
  end

  test "picker with an unknown provider returns an empty frame instead of erroring" do
    project = team.projects.create!(name: "Metis")
    get picker_project_path(project, provider: "notion")
    assert_response :success
    assert_select "turbo-frame#project_#{project.id}_picker_notion"
  end

  test "picker on another team's project is not accessible" do
    other = Team.create!(name: "Other")
    foreign = other.projects.create!(name: "Secret")
    get picker_project_path(foreign, provider: "github")
    assert_response :not_found
  end
end
