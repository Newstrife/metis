# Accept a team invitation from its tokenized link. Requires sign-in
# (Devise stores the link and returns here after auth) and that the
# signed-in user's email matches the address the invite was sent to.
class InvitationsController < ApplicationController
  layout "settings"

  def show
    @invitation = Invitation.find_by!(token: params[:token])
    redirect_if_settled(@invitation)
  end

  def accept
    invitation = Invitation.find_by!(token: params[:token])
    return if redirect_if_settled(invitation)

    return redirect_to(root_path, alert: "That invitation has expired.") if invitation.expired?
    unless invitation.for?(current_user)
      return redirect_to invitation_path(invitation.token),
                         alert: "This invitation was sent to #{invitation.email}."
    end

    invitation.accept!(current_user)
    session[:current_team_id] = invitation.team_id
    redirect_to root_path, notice: "You've joined #{invitation.team.name}."
  end

  private

  # An already-accepted invite shouldn't 404 on a double-submit or back —
  # send the user home, into the team if they're a member of it.
  def redirect_if_settled(invitation)
    return false unless invitation.accepted?

    if invitation.team.members.include?(current_user)
      session[:current_team_id] = invitation.team_id
      redirect_to root_path, notice: "You're already in #{invitation.team.name}."
    else
      redirect_to root_path, alert: "That invitation has already been used."
    end
    true
  end
end
