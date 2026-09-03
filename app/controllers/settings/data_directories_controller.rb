class Settings::DataDirectoriesController < ApplicationController
  layout "settings"

  # Knowledge-base directory registry — each row is one permission unit
  # (a subdirectory under the knowledge root). Superuser-only.
  before_action :require_superuser!

  def index
    @directories = DataDirectory.includes(:roles).order(:id)
    @directory = DataDirectory.new
  end

  def create
    @directory = DataDirectory.new(directory_params)
    if @directory.save
      redirect_to data_directories_path, notice: t("flash.settings.data_directories.create.notice", name: @directory.name)
    else
      redirect_to data_directories_path, alert: t("flash.settings.data_directories.save.failure", errors: @directory.errors.full_messages.to_sentence)
    end
  end

  def destroy
    directory = DataDirectory.find(params[:id])
    directory.destroy
    redirect_to data_directories_path, notice: t("flash.settings.data_directories.destroy.notice", name: directory.name)
  end

  private

  def directory_params
    params.require(:data_directory).permit(:name, :path, :description, :public_access)
  end
end
