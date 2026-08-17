require "test_helper"

class Settings::FeaturesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "feat-admin-#{SecureRandom.hex(4)}@example.com", password: "password123", superuser: true)
    @member = User.create!(email: "feat-member-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  teardown { Setting.delete_all }

  test "superuser sees the feature cards" do
    sign_in @admin
    get features_path
    assert_response :success
    assert_select ".settings-card", Setting::MODULES.size
  end

  test "non-superuser is turned away" do
    sign_in @member
    get features_path
    assert_redirected_to models_path
  end

  test "toggling a boolean module" do
    sign_in @admin
    patch features_path, params: { key: "wecom.auto_provision", value: "false" }
    assert_equal false, Setting.get("wecom.auto_provision")
    patch features_path, params: { key: "wecom.auto_provision", value: "true" }
    assert_equal true, Setting.get("wecom.auto_provision")
  end

  test "adding and removing whitelist entries" do
    sign_in @admin
    patch features_path, params: { key: "wecom.group_whitelist", item: "wrGroupA" }
    assert_equal %w[wrGroupA], Setting.get("wecom.group_whitelist")
    patch features_path, params: { key: "wecom.group_whitelist", remove: "wrGroupA" }
    assert_equal [], Setting.get("wecom.group_whitelist")
  end

  test "unknown module keys 404" do
    sign_in @admin
    patch features_path, params: { key: "nope", value: "true" }
    assert_response :not_found
  end
end
