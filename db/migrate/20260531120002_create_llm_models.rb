class CreateLlmModels < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_models do |t|
      t.references :llm_provider, null: false, foreign_key: true
      t.string :key, null: false
      t.string :label, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.integer :context_window
      t.integer :max_tokens
      t.boolean :reasoning, null: false, default: false
      t.jsonb :input_modalities, null: false, default: []
      t.jsonb :cost, null: false, default: {}
      t.datetime :last_seen_at

      t.timestamps
    end
    add_index :llm_models, %i[llm_provider_id key], unique: true
    # At most one deployment-wide default model.
    add_index :llm_models, :is_default, unique: true, where: "is_default"
  end
end
