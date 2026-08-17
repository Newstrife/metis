class Settings::FeaturesController < ApplicationController
  layout "settings"

  # Feature switches are deployment-level — same gate as user administration.
  before_action :require_superuser!

  def show
    @modules = Setting::MODULES
  end

  def update
    mod = Setting::MODULES[params[:key].to_s]
    return head :not_found unless mod

    case mod[:type]
    when :boolean
      Setting.set(params[:key], params[:value])
    when :list
      list = Setting.get(params[:key])
      list = (list - [ params[:remove].to_s ]) if params[:remove].present?
      list = (list + [ params[:item] ]).uniq if params[:item].present?
      Setting.set(params[:key], list)
    end
    redirect_to features_path
  end
end
