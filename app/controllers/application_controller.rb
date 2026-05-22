class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!

  private

  # The conversation list the shell sidebar renders on every page using
  # the "chat" layout. Controllers opt in with `before_action`.
  def set_sidebar
    @conversations = current_user.conversations.recent
  end
end
