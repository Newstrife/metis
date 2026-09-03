class Settings::RolesController < ApplicationController
  layout "settings"

  # Data-access role administration — superuser-only, same gate as
  # deployment-level user management.
  before_action :require_superuser!
  before_action :set_role, only: %i[update destroy]

  def index
    @roles = Role.includes(:data_directories, :users).order(:id)
    @directories = DataDirectory.order(:id)
    @role = Role.new
  end

  def create
    @role = Role.new(role_params)
    if @role.save
      redirect_to roles_path, notice: t("flash.settings.roles.create.notice", name: @role.name)
    else
      redirect_to roles_path, alert: t("flash.settings.roles.save.failure", errors: @role.errors.full_messages.to_sentence)
    end
  end

  def update
    if @role.update(role_params)
      redirect_to roles_path, notice: t("flash.settings.roles.update.notice", name: @role.name)
    else
      redirect_to roles_path, alert: t("flash.settings.roles.save.failure", errors: @role.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @role.destroy
    redirect_to roles_path, notice: t("flash.settings.roles.destroy.notice", name: @role.name)
  end

  private

  def set_role
    @role = Role.find(params[:id])
  end

  def role_params
    params.require(:role).permit(:name, :description, :full_access, data_directory_ids: [])
  end
end
