class ApplicationController < ActionController::Base
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!
  around_action :with_user_locale
  around_action :with_user_timezone

  # Page size for the sidebar conversation list — small enough that the
  # first paint is cheap, big enough that a fresh user rarely sees the
  # endless-scroll fetch fire at all.
  SIDEBAR_PAGE_SIZE = 30

  private

  # Render the request in the signed-in user's chosen locale, falling
  # back to the app default when unset or signed-out.
  def with_user_locale(&block)
    locale = current_user&.language.presence || I18n.default_locale
    I18n.with_locale(locale, &block)
  end

  # Render timestamps in the signed-in user's IANA timezone. Unset
  # falls through to the app default — the per-request scope keeps
  # background jobs unaffected.
  def with_user_timezone(&block)
    zone = current_user&.timezone.presence
    return yield unless zone

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
      current_user.conversations.recent,
      limit: SIDEBAR_PAGE_SIZE
    )
  end
end
