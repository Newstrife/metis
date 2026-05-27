# Team-managed skills — a user-authored counterpart to the repo's
# .pi/skills/ tree. Each row is a directory pi will see under
# workspace/.pi/skills/<slug>/, projected per turn by
# Agent::Workspace#stage_skills. See docs/skills.md.
class CreateSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skills do |t|
      t.references :team, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.string  :slug, null: false
      t.string  :description
      t.text    :content_cache
      t.jsonb   :examples, default: [], null: false
      t.jsonb   :metadata, default: {}, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :skills, [ :team_id, :slug ], unique: true
  end
end
