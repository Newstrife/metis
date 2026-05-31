require "test_helper"

class LlmModelTest < ActiveSupport::TestCase
  setup { @provider = LlmProvider.create!(key: "p", label: "P") }

  test "key is unique within a provider" do
    @provider.llm_models.create!(key: "m", label: "M")
    dup = @provider.llm_models.build(key: "m", label: "M2")

    assert_not dup.valid?
  end

  test "make_default sets one default and clears any other" do
    a = @provider.llm_models.create!(key: "a", label: "A", is_default: true)
    b = @provider.llm_models.create!(key: "b", label: "B")

    b.make_default!

    assert b.reload.is_default?
    assert_not a.reload.is_default?
    assert_equal b, LlmModel.current_default
  end

  test "make_default enables a disabled model" do
    model = @provider.llm_models.create!(key: "m", label: "M", enabled: false)

    model.make_default!

    assert model.reload.enabled?
  end

  test "current_default ignores a disabled default" do
    model = @provider.llm_models.create!(key: "m", label: "M", is_default: true)
    model.update_column(:enabled, false)

    assert_nil LlmModel.current_default
  end
end
