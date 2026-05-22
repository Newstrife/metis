# Manages a team's MCP connectors (docs/connectors.md). v1 scopes to the
# current user's personal team; a team switcher arrives with shared teams.
class ConnectorsController < ApplicationController
  layout "chat"

  before_action :set_sidebar
  before_action :set_connector, only: %i[edit update destroy]

  def index
    @connectors = team.connectors.order(:name)
  end

  def new
    @connector = team.connectors.new(transport: :stdio)
  end

  def create
    @connector = team.connectors.new(connector_params)
    if @connector.save
      redirect_to edit_connector_path(@connector), notice: "Connector created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @connector.update(connector_params)
      redirect_to edit_connector_path(@connector), notice: "Connector saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @connector.destroy
    redirect_to connectors_path, notice: "Connector removed."
  end

  private

  def team
    current_user.personal_team
  end

  def set_connector
    @connector = team.connectors.find(params[:id])
  end

  # The structured form posts transport-specific fields; assemble them
  # into the `definition` jsonb the model stores.
  def connector_params
    form = params.require(:connector).permit(:name, :transport, :enabled, :command, :args, :url)
    {
      name: form[:name], transport: form[:transport],
      enabled: form.fetch(:enabled, true),
      definition: definition_from(form)
    }
  end

  def definition_from(form)
    case form[:transport]
    when "stdio"
      { "command" => form[:command].to_s.strip,
        "args" => form[:args].to_s.split("\n").map(&:strip).reject(&:blank?) }
    when "http"
      { "url" => form[:url].to_s.strip }
    else
      {}
    end
  end
end
