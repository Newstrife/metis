require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @inviter = User.create!(email: "owner@example.com", password: "password123")
    @team = Team.create!(name: "Acme")
    @inviter.memberships.create!(team: @team, role: :owner)
  end

  def build_invitation(attrs = {})
    @team.invitations.new({ email: "new@example.com", role: :member, invited_by: @inviter }.merge(attrs))
  end

  test "sets a token and expiry on create, and downcases the email" do
    invitation = build_invitation(email: "  New@Example.com ")
    assert invitation.save
    assert invitation.token.present?
    assert invitation.expires_at.future?
    assert_equal "new@example.com", invitation.email
  end

  test "rejects an owner role" do
    invitation = build_invitation(role: :owner)
    assert_not invitation.valid?
    assert_includes invitation.errors[:role], "is not included in the list"
  end

  test "rejects a malformed email" do
    assert_not build_invitation(email: "not-an-email").valid?
  end

  test "rejects a second pending invitation for the same email" do
    build_invitation.save!
    assert_not build_invitation.valid?
  end

  test "rejects inviting an existing member" do
    member = User.create!(email: "member@example.com", password: "password123")
    @team.memberships.create!(user: member, role: :member)
    assert_not build_invitation(email: "member@example.com").valid?
  end

  test "accept! creates a membership with the invited role and stamps accepted_at" do
    invitation = build_invitation(role: :admin)
    invitation.save!
    user = User.create!(email: "new@example.com", password: "password123")

    assert_difference -> { @team.memberships.count }, 1 do
      invitation.accept!(user)
    end
    assert @team.memberships.find_by(user: user).admin?
    assert invitation.accepted_at.present?
    assert_empty Invitation.pending.where(id: invitation.id)
  end

  test "accept! is idempotent when the user is already a member" do
    invitation = build_invitation
    invitation.save!
    user = User.create!(email: "new@example.com", password: "password123")
    @team.memberships.create!(user: user, role: :admin)

    assert_no_difference -> { @team.memberships.count } do
      invitation.accept!(user)
    end
    assert @team.memberships.find_by(user: user).admin? # keeps existing role
  end
end
