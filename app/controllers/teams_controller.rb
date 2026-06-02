class TeamsController < ApplicationController
  # Set the active team for subsequent requests. Scoped to the user's
  # own teams, so a non-member id 404s rather than switching
  # (docs/tenancy.md).
  def switch
    team = current_user.teams.find(params[:id])
    session[:current_team_id] = team.id
    redirect_back fallback_location: root_path
  end
end
