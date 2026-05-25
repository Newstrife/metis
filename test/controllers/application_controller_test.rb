require "test_helper"

# The around-actions ApplicationController wraps every request in. We
# unit-test the methods directly rather than routing a probe action,
# because the contract is straightforward (take a block, yield inside
# a scoped Time.zone / I18n.locale) and a probe would mostly verify
# Rails' own around_action plumbing rather than our logic.
class ApplicationControllerTest < ActiveSupport::TestCase
  def setup
    @controller = ApplicationController.new
  end

  def stub_current_user(user)
    @controller.define_singleton_method(:current_user) { user }
  end

  test "with_user_timezone yields inside the user's zone" do
    user = User.create!(email: "tz1-#{SecureRandom.hex(4)}@example.com",
                        password: "password123", timezone: "Tokyo")
    stub_current_user(user)

    observed = nil
    @controller.send(:with_user_timezone) { observed = Time.zone.name }
    assert_equal "Tokyo", observed
  end

  test "with_user_timezone falls through when the user has none" do
    user = User.create!(email: "tz2-#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    stub_current_user(user)
    default = Time.zone.name

    observed = nil
    @controller.send(:with_user_timezone) { observed = Time.zone.name }
    assert_equal default, observed
  end

  # detect_timezone bypasses model validation via update_column, so a
  # bad value can land in users.timezone. Without the TimeZone[] guard
  # in with_user_timezone, Time.use_zone would raise on every request
  # and 500 the entire chat shell.
  test "with_user_timezone does not raise when the stored zone is unknown" do
    user = User.create!(email: "tz3-#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.update_column(:timezone, "Nowhere/Real")
    stub_current_user(user)
    default = Time.zone.name

    observed = nil
    assert_nothing_raised do
      @controller.send(:with_user_timezone) { observed = Time.zone.name }
    end
    assert_equal default, observed, "should silently fall back, not raise"
  end

  test "with_user_locale yields inside the user's locale" do
    user = User.create!(email: "loc-#{SecureRandom.hex(4)}@example.com",
                        password: "password123", language: "en")
    stub_current_user(user)

    observed = nil
    @controller.send(:with_user_locale) { observed = I18n.locale }
    assert_equal :en, observed
  end

  test "with_user_locale falls back to the app default when language is blank" do
    user = User.create!(email: "loc2-#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    stub_current_user(user)

    observed = nil
    @controller.send(:with_user_locale) { observed = I18n.locale }
    assert_equal I18n.default_locale, observed
  end
end
