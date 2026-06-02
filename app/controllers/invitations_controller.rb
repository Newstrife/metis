# Accept a team invitation from its tokenized link. Requires sign-in
# (Devise stores the link and returns here after auth) and that the
# signed-in user's email matches the address the invite was sent to.
class InvitationsController < ApplicationController
  layout "settings"

  def show
    @invitation = Invitation.pending.find_by!(token: params[:token])
  end

  def accept
    invitation = Invitation.pending.find_by!(token: params[:token])

    return redirect_to(root_path, alert: "That invitation has expired.") if invitation.expired?
    unless invitation.email == current_user.email.to_s.downcase
      return redirect_to invitation_path(invitation.token),
                         alert: "This invitation was sent to #{invitation.email}."
    end

    invitation.accept!(current_user)
    session[:current_team_id] = invitation.team_id
    redirect_to root_path, notice: "You've joined #{invitation.team.name}."
  end
end
