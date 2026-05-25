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
  # yet \u2014 the browser sends back its IANA zone so first-paint
  # timestamps match the user's wall clock without making them open
  # the settings page. No-op if the user already picked one.
  def detect_timezone
    submitted = params[:timezone].to_s
    if current_user.timezone.blank? && submitted.present? &&
       ActiveSupport::TimeZone[submitted]
      current_user.update_column(:timezone, submitted)
    end
    head :no_content
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :timezone, :language, :preferred_model)
  end
end
