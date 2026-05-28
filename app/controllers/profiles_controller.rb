class ProfilesController < ApplicationController
  layout "settings"

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

  # Inline avatar upload / remove from the profile page's avatar editor.
  # Lives at its own endpoint so the rest of the profile form (which
  # the user may be mid-edit in) is not disturbed by the AJAX swap.
  def update_avatar
    @user = current_user
    if ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remove_avatar))
      @user.update(remove_avatar: "1")
    elsif (file = params.dig(:user, :avatar)).present?
      @user.update(avatar: file)
    end

    respond_to do |format|
      format.turbo_stream
    end
  end

  # Live theme switch from the user-menu popup — no full form roundtrip.
  # Unknown values are silently dropped (theme is a UI affordance, not
  # something to error on).
  def update_theme
    theme = params[:theme].to_s
    current_user.update!(theme: theme) if User::THEMES.include?(theme)
    head :no_content
  end

  # Browser sends IANA ("Europe/Berlin"); the model validator + time_zone_select
  # only know Rails-friendly names ("Berlin"), so canonicalize before persisting.
  def detect_timezone
    canonical = canonical_zone_name(params[:timezone].to_s)
    if current_user.timezone.blank? && canonical
      current_user.update_column(:timezone, canonical)
    end
    head :no_content
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :timezone, :language, :preferred_model,
                                 :theme, :about_you, :custom_instructions)
  end

  # IANA or Rails-friendly \u2192 Rails-friendly (the form the model validator accepts),
  # via MAPPING inverted on tzinfo's identifier. nil for unknown zones.
  def canonical_zone_name(submitted)
    zone = ActiveSupport::TimeZone[submitted]
    return nil unless zone

    ActiveSupport::TimeZone::MAPPING.invert[zone.tzinfo.identifier]
  end
end
