class ProjectsController < ApplicationController
  layout "settings"

  before_action :set_project, only: %i[edit update destroy]

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
    @repo_options   = ResourcePicker::Github.list(user: current_user)
    @linear_options = ResourcePicker::Linear.list(user: current_user)
  end

  def update
    @project.assign_attributes(project_params)
    @project.updated_by = current_user

    if @project.save
      redirect_to edit_project_path(@project), notice: "Project saved."
    else
      @repo_options   = ResourcePicker::Github.list(user: current_user)
      @linear_options = ResourcePicker::Linear.list(user: current_user)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @project.name
    @project.destroy
    redirect_to projects_path, notice: "#{name} deleted."
  end

  private

  def team
    current_user.personal_team
  end

  def set_project
    @project = team.projects.find(params[:id])
  end

  # external_refs comes through the form as nested fields keyed by
  # connector type (github, linear). Each connector's sub-hash is
  # narrowly permitted to the ref shape that connector type uses —
  # mass assignment cannot inject arbitrary nested keys.
  def project_params
    permitted = params.require(:project).permit(:name, :about,
                                                  external_refs: { github: [ :repo ], linear: [ :project_id ] })
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
