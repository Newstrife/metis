require "test_helper"

class ModelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @provider = LlmProvider.create!(key: "openai-codex", label: "OpenAI Codex")
    @model = @provider.llm_models.create!(key: "gpt-5.5", label: "GPT-5.5")
    @admin = User.create!(email: "admin-#{SecureRandom.hex(4)}@example.com",
                          password: "password123", admin: true)
    @member = User.create!(email: "member-#{SecureRandom.hex(4)}@example.com",
                           password: "password123", admin: false)
  end

  test "index renders for a non-admin member" do
    sign_in @member
    get models_path

    assert_response :success
    assert_select "h1.pane-title", "Models"
  end

  test "a member cannot toggle a model" do
    sign_in @member
    patch model_item_path(@model), params: { enabled: false }

    assert_redirected_to models_path
    assert @model.reload.enabled?
  end

  test "a member cannot refresh" do
    sign_in @member
    post refresh_models_path

    assert_redirected_to models_path
    assert_equal "Only an administrator can change the model catalog.", flash[:alert]
  end

  test "an admin toggles a model" do
    sign_in @admin
    patch model_item_path(@model), params: { enabled: false }

    assert_not @model.reload.enabled?
  end

  test "an admin toggles a provider, cascading to its models" do
    sign_in @admin
    patch model_provider_path(@provider), params: { enabled: false }

    assert_not @provider.reload.enabled?
    assert_not @model.reload.enabled?
  end

  test "an admin sets the default model" do
    sign_in @admin
    post model_item_default_path(@model)

    assert @model.reload.is_default?
  end

  test "refresh surfaces an unreachable pi" do
    sign_in @admin
    with_stub(PiAgent, :session, ->(*, **) { raise "no pi" }) do
      post refresh_models_path
    end

    assert_redirected_to models_path
    assert_equal "Couldn't reach pi — the catalog was not changed.", flash[:alert]
  end
end
