class SkillsController < ApplicationController
  layout "settings"

  before_action :set_skill, only: %i[edit update destroy add_file destroy_file download_file]

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

  # Attach a new supporting file to the skill. SKILL.md is reserved
  # for the textarea on the edit form; everything else lives here.
  def add_file
    path = params[:path].to_s.strip
    upload = params[:file]

    unless upload.respond_to?(:read)
      return redirect_to edit_skill_path(@skill), alert: "Pick a file to upload."
    end
    unless Skill.valid_file_path?(path)
      return redirect_to edit_skill_path(@skill), alert: "Invalid path — use a relative path under #{Skill::MAX_FILE_PATH_DEPTH} levels, segments like `ref/style.md`."
    end
    if upload.size > Skill::MAX_FILE_SIZE
      return redirect_to edit_skill_path(@skill),
             alert: "File too large — keep it under #{Skill::MAX_FILE_SIZE / 1.megabyte}MB."
    end

    @skill.replace_file!(path, upload.read, upload.content_type.presence)
    @skill.update!(updated_by: current_user)
    redirect_to edit_skill_path(@skill), notice: "Added #{path}."
  end

  def destroy_file
    attachment = @skill.files.find_by(id: params[:file_id])
    return redirect_to edit_skill_path(@skill), alert: "File not found." unless attachment

    rel = @skill.relative_path(attachment)
    attachment.purge
    @skill.update!(updated_by: current_user)
    redirect_to edit_skill_path(@skill), notice: "Removed #{rel}."
  end

  # Stream the blob inline so previewable text shows up in the browser
  # tab; the browser falls back to download for binary types.
  def download_file
    attachment = @skill.files.find_by(id: params[:file_id])
    return head :not_found unless attachment

    send_data attachment.download,
              filename: File.basename(@skill.relative_path(attachment)),
              type: attachment.content_type,
              disposition: "inline"
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
