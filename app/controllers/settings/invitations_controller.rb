# Send and revoke invitations for the active team. Acceptance lives in
# the top-level InvitationsController (the invitee may not be a member
# of this team yet).
class Settings::InvitationsController < ApplicationController
  before_action :require_team_admin!

  def create
    return redirect_to team_path, alert: "Create a team before inviting people." if current_team.personal?

    invitation = current_team.invitations.new(invitation_params)
    invitation.invited_by = current_user
    if invitation.save
      TeamMailer.invitation(invitation).deliver_later
      redirect_to team_path, notice: "Invitation sent to #{invitation.email}."
    else
      redirect_to team_path, alert: invitation.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_team.invitations.find(params[:id]).destroy
    redirect_to team_path, notice: "Invitation revoked."
  end

  private

  def invitation_params
    params.require(:invitation).permit(:email, :role)
  end
end
