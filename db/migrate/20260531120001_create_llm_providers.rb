class CreateLlmProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_providers do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :llm_providers, :key, unique: true
  end
end
