class ProjectsController < ApplicationController
  layout "settings"

  before_action :set_project, only: %i[edit update destroy picker]
  before_action :load_available_providers, only: %i[new create edit update]

  def index
    @projects = team.projects.recent
  end

  def new
    @project = team.projects.new
  end

  def create
    @project = team.projects.new(project_params)
    @project.created_by = current_user
    @project.updated_by = current_user

    if @project.save
      redirect_to edit_project_path(@project), notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @project.assign_attributes(project_params)
    @project.updated_by = current_user

    if @project.save
      redirect_to edit_project_path(@project), notice: "Project saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @project.name
    @project.destroy
    redirect_to projects_path, notice: "#{name} deleted."
  end

  # GET /settings/projects/:id/picker?provider=github — turbo-frame
  # endpoint hit eagerly by the edit form. Each provider's resources
  # are fetched on its own request so the page doesn't block waiting
  # for both APIs in series. Unknown providers render an empty frame
  # (the partial's case/when falls through) — better than a 500.
  def picker
    render_picker_for(@project)
  end

  # GET /settings/projects/new/picker?provider=github — collection
  # counterpart for the New project form, where the project isn't
  # persisted yet so the member route can't be used. The unpersisted
  # project carries no stored external_refs, so the picker renders
  # with no value selected.
  def new_picker
    render_picker_for(team.projects.new)
  end

  private

  def team
    current_user.personal_team
  end

  def set_project
    @project = team.projects.find(params[:id])
  end

  # A provider is offerable in the picker only when the team has the
  # connector installed AND the current user has an OAuth grant for it.
  # Without both, hitting the picker action would just render an empty
  # state — so we suppress the placeholder upstream and tell the user
  # to connect first instead.
  def render_picker_for(project)
    provider = params[:provider].to_s
    picker = ResourcePicker.for(provider)
    options = picker ? picker.list(user: current_user) : []
    render partial: "projects/picker",
           locals: { project: project, provider: provider, options: options }
  end

  def load_available_providers
    keys = ResourcePicker::PROVIDERS.keys
    installed = team.connectors.where(catalog_key: keys).pluck(:catalog_key)
    authorized = current_user.oauth_grants.where(provider: keys).pluck(:provider)
    @available_providers = installed & authorized
  end

  # external_refs comes through the form as nested fields keyed by
  # connector type. The permitted shape is derived from the
  # ResourcePicker registry, so each connector's sub-hash only allows
  # that connector's REF_FIELD — mass assignment cannot inject
  # arbitrary nested keys, and adding a connector means zero edits
  # here.
  def project_params
    permitted = params.require(:project).permit(:name, :about,
                                                  external_refs: ResourcePicker.strong_params_shape)
    permitted[:external_refs] = sanitize_external_refs(permitted[:external_refs])
    permitted
  end

  def sanitize_external_refs(refs)
    return {} if refs.blank?

    refs = refs.to_h
    refs.each_with_object({}) do |(connector, values), out|
      values = values.to_h.reject { |_, v| v.to_s.strip.empty? }
      out[connector.to_s] = values unless values.empty?
    end
  end
end
