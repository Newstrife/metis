class Settings::UsersController < ApplicationController
  layout "settings"

  # Deployment-level account administration — superuser-only (granted
  # out-of-band via `rake superuser:grant`), never a team role.
  before_action :require_superuser!
  before_action :set_user, only: %i[update destroy]

  def index
    @users = User.order(:id)
    @roles = Role.order(:id)
  end

  # Admin-initiated password reset (WeCom-provisioned accounts can't use
  # the email reset flow — their @wecom.local address is synthetic) and
  # data_group (hard-permission clearance) assignment. Blank fields are
  # left untouched so the two forms on the page stay independent.
  def update
    attrs = user_params.to_h.compact_blank
    # 角色复选框的隐藏空值；空数组 = 清空该用户的全部角色
    attrs["role_ids"] = Array(attrs["role_ids"]).reject(&:blank?) if attrs.key?("role_ids")
    if @user.update(attrs)
      redirect_to users_path, notice: t("flash.settings.users.update.notice", email: @user.email)
    else
      redirect_to users_path, alert: t("flash.settings.users.update.failure", errors: @user.errors.full_messages.to_sentence)
    end
  end

  def destroy
    if @user == current_user
      return redirect_to users_path, alert: t("flash.settings.users.destroy.self")
    end
    # Mirror AccountsController#destroy: the personal team-of-one goes
    # with the account; shared teams keep going without the membership.
    @user.personal_team&.destroy
    @user.destroy
    redirect_to users_path, notice: t("flash.settings.users.destroy.notice", email: @user.email)
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:password, role_ids: [])
  end
end
