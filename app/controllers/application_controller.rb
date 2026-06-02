class ApplicationController < ActionController::Base
  include Pagy::Method

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  around_action :with_user_locale, if: :user_signed_in?
  around_action :with_user_timezone, if: :user_signed_in?

  helper_method :current_team, :current_membership

  SIDEBAR_PAGE_SIZE = 30

  private

  # The team this request acts in. Session-backed and always validated
  # against membership, so a stale or forged id can never reach a team
  # the user isn't in (docs/tenancy.md). Falls back to the personal
  # team-of-one when nothing is selected.
  def current_team
    @current_team ||=
      (session[:current_team_id] && current_user.teams.find_by(id: session[:current_team_id])) ||
      current_user.personal_team
  end

  def current_membership
    @current_membership ||= current_user.memberships.find_by(team: current_team)
  end

  def require_team_admin!
    return if current_membership&.manages_team?

    redirect_to team_path, alert: "You don't have permission to manage this team."
  end

  def require_team_owner!
    return if current_membership&.owner?

    redirect_to team_path, alert: "Only the team owner can do that."
  end

  # Roster operations (rename, delete, invite, leave) only make sense on
  # a shared team — a personal workspace is a team-of-one.
  def reject_personal_team!
    return unless current_team.personal?

    redirect_to team_path, alert: "That isn't available for your personal workspace."
  end

  # Cast a request param to a real boolean ("1"/"true"/"on" -> true, etc.).
  def boolean_param(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def with_user_locale(&block)
    I18n.with_locale(current_user.language.presence || I18n.default_locale, &block)
  end

  # TimeZone[] guard: detect_timezone bypasses validation via update_column,
  # and Time.use_zone raises on unknown identifiers.
  def with_user_timezone(&block)
    zone = current_user.timezone.presence
    return yield unless zone && ActiveSupport::TimeZone[zone]

    Time.use_zone(zone, &block)
  end

  # :countless (LIMIT+1 probe, no COUNT). Don't switch to headless: true —
  # that drops the probe and `@sidebar_pagy.next` goes nil.
  def set_sidebar
    @sidebar_pagy, @conversations = pagy(
      :countless,
      current_user.conversations.for_team(current_team).active.recent,
      limit: SIDEBAR_PAGE_SIZE
    )
  end
end
