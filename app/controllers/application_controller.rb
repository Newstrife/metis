class ApplicationController < ActionController::Base
  include Pagy::Method

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  around_action :with_user_locale, if: :user_signed_in?
  around_action :with_user_timezone, if: :user_signed_in?

  SIDEBAR_PAGE_SIZE = 30

  private

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
      current_user.conversations.active.recent,
      limit: SIDEBAR_PAGE_SIZE
    )
  end
end
