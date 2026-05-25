class ApplicationController < ActionController::Base
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!
  around_action :with_user_locale, if: :user_signed_in?
  around_action :with_user_timezone, if: :user_signed_in?

  # Page size for the sidebar conversation list — small enough that the
  # first paint is cheap, big enough that a fresh user rarely sees the
  # endless-scroll fetch fire at all.
  SIDEBAR_PAGE_SIZE = 30

  private

  # Render the request in the signed-in user's chosen locale, falling
  # back to the app default when they haven't picked one. The
  # `if: :user_signed_in?` guard on the around_action keeps signed-out
  # paths (devise, public errors) out of here entirely.
  def with_user_locale(&block)
    I18n.with_locale(current_user.language.presence || I18n.default_locale, &block)
  end

  # Render timestamps in the user's timezone. Same `user_signed_in?`
  # gate as above. Falls through unchanged when the user hasn't picked
  # a zone, OR when the stored string isn't one Rails recognises —
  # `Time.use_zone` raises on unknown identifiers, and
  # ProfilesController#detect_timezone bypasses model validation via
  # `update_column`, so a bad value would 500 the whole chat shell on
  # every request without the TimeZone[] guard.
  def with_user_timezone(&block)
    zone = current_user.timezone.presence
    return yield unless zone && ActiveSupport::TimeZone[zone]

    Time.use_zone(zone, &block)
  end

  # The conversation list the shell sidebar renders on every page using
  # the "chat" layout. Controllers opt in with `before_action`.
  #
  # Paginated with Pagy's :countless paginator so we never run a COUNT
  # over the user's full history just to render the sidebar — it uses
  # a LIMIT+1 probe instead, so `@sidebar_pagy.next` is populated. (Do
  # not pass `headless: true`: that mode drops the +1 probe and demands
  # callers compare `@records.size` against `:limit` themselves.)
  def set_sidebar
    @sidebar_pagy, @conversations = pagy(
      :countless,
      current_user.conversations.active.recent,
      limit: SIDEBAR_PAGE_SIZE
    )
  end
end
