class TeamMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @team = invitation.team
    @inviter = invitation.invited_by
    @accept_url = accept_invitation_url(invitation.token)

    mail to: invitation.email,
         subject: "#{@inviter.display_label} invited you to #{@team.name} on Metis"
  end
end
