# Team-owned named bundles of (about, external_refs). A Conversation
# may optionally belong_to one. external_refs is sparse, keyed by
# connector catalog_key, and tells the agent which external resource
# (GitHub repo, Linear project, ...) is the SSOT for this project —
# surfaced to the agent through the project layer of AGENTS.md
# (Agent::Identity).
class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :team, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text   :about
      t.jsonb  :external_refs, null: false, default: {}

      t.timestamps
    end

    add_index :projects, [ :team_id, :name ], unique: true
  end
end
