# The deployment's LLM catalog under /settings — list providers/models,
# refresh from pi, toggle availability, and set the default. The page is
# readable by any member; mutations are superuser-only.
class ModelsController < ApplicationController
  layout "settings"

  before_action :require_superuser!, except: :index

  def index
    @providers = LlmProvider.ordered.includes(:llm_models)
    @default_model = LlmModel.current_default
  end

  def refresh
    result = Agent::ModelCatalogSync.call
    if result[:ok]
      redirect_to models_path, notice: "Synced #{result[:models]} models from pi."
    else
      redirect_to models_path, alert: "Couldn't reach pi — the catalog was not changed."
    end
  end

  def update_provider
    LlmProvider.find(params[:id]).set_enabled!(boolean_param(params[:enabled]))
    redirect_to models_path
  end

  def update_model
    model = LlmModel.find(params[:id])
    model.update!(enabled: boolean_param(params[:enabled]))
    redirect_to models_path
  end

  def make_default
    LlmModel.find(params[:id]).make_default!
    redirect_to models_path
  rescue ActiveRecord::RecordNotUnique
    redirect_to models_path,
                alert: "Another superuser changed the default model. Please try again."
  end
end
