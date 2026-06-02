# Manage who's on the active team: change a member's role, remove a
# member, transfer ownership, or leave. The owner is special — never
# demoted or removed directly, so a team always has exactly one owner
# (docs/tenancy.md).
class Settings::MembershipsController < ApplicationController
  before_action :require_team_admin!, only: %i[update destroy]
  before_action :require_team_owner!, only: :transfer
  before_action :reject_personal_team!, only: :leave

  def update
    membership = current_team.memberships.find(params[:id])
    return reject("You can't change the owner's role.") if membership.owner?

    # role is read straight off params (not strong-params) and checked
    # against an allowlist — never mass-assigned, since it grants privilege.
    role = params.dig(:membership, :role)
    return reject("That role can't be assigned.") unless Membership::ASSIGNABLE_ROLES.include?(role)

    membership.update!(role: role)
    redirect_to team_path, notice: "#{membership.user.display_label} is now #{role}."
  end

  def destroy
    membership = current_team.memberships.find(params[:id])
    return reject("The owner can't be removed.") if membership.owner?
    return reject("Use “Leave team” to remove yourself.") if membership.user_id == current_user.id

    membership.destroy
    redirect_to team_path, notice: "#{membership.user.display_label} removed."
  end

  def transfer
    target = current_team.memberships.find(params[:id])
    return reject("They're already the owner.") if target.owner?

    current_team.transfer_ownership!(from: current_membership, to: target)
    redirect_to team_path, notice: "#{target.user.display_label} is now the owner."
  end

  def leave
    membership = current_team.memberships.find_by!(user: current_user)
    return reject("Transfer ownership or delete the team before leaving.") if membership.owner?

    name = current_team.name
    membership.destroy
    session.delete(:current_team_id)
    redirect_to team_path, notice: "You left #{name}."
  end

  private

  def reject(message)
    redirect_to team_path, alert: message
  end
end
