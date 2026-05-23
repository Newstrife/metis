# The connector marketplace (docs/connectors.md): a gallery of catalog
# apps, the connect flow, and per-connector management. v1 scopes to the
# user's personal team; a team switcher arrives with shared teams.
class ConnectorsController < ApplicationController
  layout "chat"

  before_action :set_sidebar
  before_action :set_connector, only: %i[edit update destroy]

  # The marketplace: catalog apps as tiles, plus the team's custom
  # connectors.
  def index
    @apps = ConnectorCatalog.all
    @connected = team.connectors.where.not(catalog_key: nil).index_by(&:catalog_key)
    @custom = team.connectors.where(catalog_key: nil).order(:name)
  end

  # `?app=<key>` opens the connect form for a catalog app; without it,
  # the custom-MCP-server form.
  def new
    if (@app = ConnectorCatalog.find(params[:app]))
      existing = team.connectors.find_by(catalog_key: @app.key)
      return redirect_to edit_connector_path(existing) if existing
      # OAuth apps connect through Devise omniauth (the marketplace tile
      # button POSTs straight to it); there's no intermediate page.
      return redirect_to connectors_path if @app.oauth?

      render :connect
    else
      @connector = team.connectors.new(transport: :stdio)
    end
  end

  def create
    if (app = ConnectorCatalog.find(params[:catalog_key]))
      connect_app(app)
    else
      create_custom
    end
  end

  # The manage page for a connected connector.
  def edit
    @app = @connector.catalog_app
    @credential = @connector.credential_for(current_user)
  end

  def update
    @connector.assign_attributes(custom_params) unless @connector.catalog_key
    if @connector.save
      save_credential
      redirect_to edit_connector_path(@connector), notice: "Connector saved."
    else
      @app = @connector.catalog_app
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @connector.destroy
    redirect_to connectors_path, notice: "#{@connector.name} disconnected."
  end

  private

  def team
    current_user.personal_team
  end

  def set_connector
    @connector = team.connectors.find(params[:id])
  end

  # --- catalog connect --------------------------------------------------

  def connect_app(app)
    # OAuth apps come through the omniauth callback, not this endpoint.
    return redirect_to(connectors_path) if app.oauth?

    connector = team.connectors.find_or_initialize_by(catalog_key: app.key)
    connector.update!(
      name: app.key, transport: app.transport,
      definition: app.resolved_definition(input_params(app))
    )
    save_app_credential(connector, app)
    redirect_to edit_connector_path(connector), notice: "#{app.name} connected."
  end

  def input_params(app)
    params.fetch(:inputs, {}).permit(*app.inputs.map { |input| input["key"] }).to_h
  end

  # The connecting member's own credential — identity-bearing apps act
  # as that member. A shared team credential is a later refinement.
  def save_app_credential(connector, app)
    secret = params[:credential]
    return if secret.blank? || app.credential.blank?

    credential = connector.connector_credentials.find_or_initialize_by(user: current_user)
    credential.update!(credential_map: app.credential_map_for(secret))
  end

  # --- custom connector -------------------------------------------------

  def create_custom
    @connector = team.connectors.new(custom_params)
    if @connector.save
      redirect_to edit_connector_path(@connector), notice: "Connector created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Custom connectors only — a catalog connector's definition is owned
  # by the catalog and has no editable structural fields here.
  def custom_params
    form = connector_form
    {
      name: form[:name], transport: form[:transport],
      definition: definition_from(form)
    }
  end

  def connector_form
    params.require(:connector).permit(:name, :transport, :command, :args, :url)
  end

  # The structured form posts transport-specific fields; assemble them
  # into the `definition` jsonb.
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

  # Re-set the member's credential when the manage page supplies one.
  # OAuth-shaped apps own their credential lifecycle through the connect
  # flow — never accept a typed-in secret for them.
  def save_credential
    app = @connector.catalog_app
    return unless app && app.token_auth? && params[:credential].present?

    credential = @connector.connector_credentials.find_or_initialize_by(user: current_user)
    credential.update!(credential_map: app.credential_map_for(params[:credential]))
  end
end
