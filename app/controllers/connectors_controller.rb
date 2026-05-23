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
    app = @connector.catalog_app
    @connector.destroy
    prune_or_revoke_oauth_grant(app) if app&.oauth?
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

  # On disconnect of an OAuth-shaped connector: revoke the grant on
  # the provider's side and destroy the local row IFF no other
  # OAuth-shaped connectors for this provider remain wired to the
  # user. Otherwise leave the grant alone.
  #
  # We deliberately do NOT prune `grant.scopes` when other connectors
  # remain — we have no way to ask Google to shrink the authorization
  # (Google's revoke is all-or-nothing), so the local scope set should
  # reflect what Google actually has, not what we *wish* they had.
  # Rewriting `scopes` locally would silently drop coverage for
  # scopes the user still legitimately holds (e.g. catalog tightened
  # mid-life, or a scope shared between two connectors gets dropped
  # when one is disconnected).
  #
  # Revoke-on-last is the part that matters: after the user disconnects
  # their last OAuth connector for a provider, the next "Sign in" or
  # "Connect" lands as a *fresh* OAuth — the only reliable way to get
  # the consent screen back (with the grant on file, `prompt=consent`
  # is silently downgraded to `prompt=none`).
  def prune_or_revoke_oauth_grant(app)
    grant = current_user.oauth_grants.find_by(provider: app.oauth_provider)
    return unless grant
    return if active_connectors_for?(app.oauth_provider)

    OauthBroker.revoke(grant)
    grant.destroy
  end

  # True if the current user still has any OAuth-shaped connector
  # wired through this provider (after the just-destroyed one was
  # cascade-removed from connector_credentials).
  def active_connectors_for?(provider)
    catalog_keys = ConnectorCatalog.all.select { |a| a.oauth_provider == provider }.map(&:key)
    current_user.connector_credentials
                .joins(:connector)
                .where(connectors: { catalog_key: catalog_keys })
                .exists?
  end
end
