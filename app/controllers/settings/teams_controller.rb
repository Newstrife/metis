# Manage the active team (current_team) — members roster, rename,
# delete. Member-level role changes and invitations live in their own
# controllers.
class Settings::TeamsController < ApplicationController
  layout "settings"

  before_action :require_team_admin!, only: :update
  before_action :require_team_owner!, only: :destroy
  before_action :reject_personal_team!, only: %i[update destroy]

  def show
    @team = current_team
    @memberships = @team.memberships.includes(user: { avatar_attachment: :blob })
    @invitation = Invitation.new
    @pending_invitations = @team.invitations.pending.order(:created_at)
  end

  def update
    current_team.update!(team_params)
    redirect_to team_path, notice: "Team renamed."
  end

  def destroy
    name = current_team.name
    current_team.destroy
    session.delete(:current_team_id) # falls back to the personal team
    redirect_to team_path, notice: "#{name} deleted."
  end

  private

  def team_params
    params.require(:team).permit(:name)
  end
end
