class ImportSkillJob < ApplicationJob
  queue_as :default

  def perform(team_id:, by_user_id:, url:)
    team = Team.find(team_id)
    by = User.find(by_user_id)
    Agent::SkillImporter.from_github(url: url, team: team, by: by)
  rescue Agent::SkillImporter::Error, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("ImportSkillJob failed (team=#{team_id}, url=#{url}): #{e.message}")
  end
end
