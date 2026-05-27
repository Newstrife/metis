class SkillsController < ApplicationController
  layout "settings"

  before_action :set_skill, only: %i[edit update destroy]

  def index
    @skills = team.skills.order(updated_at: :desc)
  end

  def new
    @skill = team.skills.new
  end

  def create
    @skill = team.skills.new(skill_params)
    @skill.created_by = current_user
    @skill.updated_by = current_user
    write_skill_md!(@skill, params.dig(:skill, :skill_md))

    if @skill.save
      redirect_to edit_skill_path(@skill), notice: "Skill created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @skill.assign_attributes(skill_params)
    @skill.updated_by = current_user
    write_skill_md!(@skill, params.dig(:skill, :skill_md))

    if @skill.save
      redirect_to edit_skill_path(@skill), notice: "Skill saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @skill.destroy
    redirect_to skills_path, notice: "#{@skill.slug} deleted."
  end

  private

  def team
    current_user.personal_team
  end

  def set_skill
    @skill = team.skills.find(params[:id])
  end

  def skill_params
    params.require(:skill).permit(:slug, :description, :enabled, examples: [])
  end

  # SKILL.md lives in Active Storage, not the skills table, so the
  # form's :skill_md textarea is written through replace_skill_md!
  # (which mirrors to content_cache). Blank means "don't touch" — the
  # row may still be saving other fields (slug, enabled).
  def write_skill_md!(skill, body)
    return if body.nil?
    skill.replace_skill_md!(body.to_s)
  end
end
