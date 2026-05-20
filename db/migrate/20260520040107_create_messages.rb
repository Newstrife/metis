class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.integer :role, null: false
      t.text :content
      t.jsonb :native_ref
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.string :tool_call_id
      t.integer :streaming_status, null: false, default: 0

      t.timestamps
    end
  end
end
