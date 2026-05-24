class ApplicationController < ActionController::Base
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!

  # Page size for the sidebar conversation list — small enough that the
  # first paint is cheap, big enough that a fresh user rarely sees the
  # endless-scroll fetch fire at all.
  SIDEBAR_PAGE_SIZE = 30

  private

  # The conversation list the shell sidebar renders on every page using
  # the "chat" layout. Controllers opt in with `before_action`.
  #
  # Paginated with Pagy's :countless paginator so we never run a COUNT
  # over the user's full history just to render the sidebar — the next
  # page is discoverable from `@sidebar_pagy.next` and the items array
  # size (see docs at ddnexus.github.io/pagy/toolbox/paginators/countless).
  def set_sidebar
    @sidebar_pagy, @conversations = pagy(
      :countless,
      current_user.conversations.recent,
      limit: SIDEBAR_PAGE_SIZE,
      headless: true
    )
  end
end
