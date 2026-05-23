require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  def user(suffix = SecureRandom.hex(4))
    User.create!(email: "id-#{suffix}@example.com", password: "password123")
  end

  test "requires provider and uid" do
    identity = Identity.new(user: user)
    assert_not identity.valid?
    assert_includes identity.errors[:provider], "can't be blank"
    assert_includes identity.errors[:uid], "can't be blank"
  end

  test "is unique per (provider, uid)" do
    user_a = user("a")
    user_b = user("b")
    user_a.identities.create!(provider: "github", uid: "5")

    duplicate = user_b.identities.build(provider: "github", uid: "5")
    assert_not duplicate.valid?

    # Same uid under a different provider is fine.
    assert user_b.identities.build(provider: "google_oauth2", uid: "5").valid?
  end

  test "a user can hold several identities across providers" do
    u = user
    u.identities.create!(provider: "github", uid: "1")
    u.identities.create!(provider: "google_oauth2", uid: "2")
    assert_equal 2, u.identities.count
  end

  test "destroying the user destroys the identities" do
    u = user
    u.identities.create!(provider: "github", uid: "1")
    assert_difference("Identity.count", -1) { u.destroy }
  end
end
