# The user's profile/settings page (FLA-13). Display name, timezone,
# language, and default model live on `users` directly; the form
# submits via Turbo so the sidebar (which renders the avatar +
# display name) updates in place without a full reload.
class ProfilesController < ApplicationController
  layout "chat"

  before_action :set_sidebar, only: %i[show update]

  def show
    @user = current_user
  end

  # `set_sidebar` runs unconditionally because three of the four
  # response paths render the sidebar partial: the turbo-stream success
  # (refreshes the avatar + display name), and both `render :show` and
  # `render :update` failure paths (the chat layout includes the
  # sidebar). Only the HTML success branch redirects without it; the
  # asymmetry isn't worth the cost of guessing right in each branch.
  def update
    @user = current_user
    @user.assign_attributes(profile_params)
    if @user.save(context: :profile_update)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Profile saved."
          render :update
        end
        format.html { redirect_to profile_path, notice: "Profile saved." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { render :show, status: :unprocessable_entity }
      end
    end
  end

  # Called once from the chat layout when a fresh user has no timezone
  # yet \u2014 the browser sends back its IANA zone so first-paint timestamps
  # match the user's wall clock without making them open the settings
  # page. No-op if the user already picked one.
  #
  # The model's inclusion validator and `time_zone_select` only know
  # Rails-friendly names ("Berlin"), but the browser sends IANA names
  # ("Europe/Berlin"). We canonicalize to the Rails-friendly form
  # before persisting, so a subsequent profile save doesn't
  # validation-fail on a field the user didn't touch, and the selector
  # has a matching option.
  def detect_timezone
    canonical = canonical_zone_name(params[:timezone].to_s)
    if current_user.timezone.blank? && canonical
      current_user.update_column(:timezone, canonical)
    end
    head :no_content
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :timezone, :language, :preferred_model)
  end

  # Map any zone string (IANA or Rails-friendly) to the Rails-friendly
  # name in ActiveSupport::TimeZone::MAPPING \u2014 the one the model
  # validator accepts. TimeZone[] resolves either form to a zone, but
  # `zone.name` preserves the input string; the canonical form lives
  # in MAPPING (Rails-friendly => IANA). Resolve through tzinfo's IANA
  # identifier and invert, so "Berlin" / "Europe/Berlin" both land on
  # "Berlin". Returns nil for unknown zones.
  def canonical_zone_name(submitted)
    zone = ActiveSupport::TimeZone[submitted]
    return nil unless zone

    ActiveSupport::TimeZone::MAPPING.invert[zone.tzinfo.identifier]
  end
end
