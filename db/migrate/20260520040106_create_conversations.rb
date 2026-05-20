class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :backend, null: false, default: 0
      t.string :title
      t.jsonb :settings, null: false, default: {}
      t.string :backend_session_id

      t.timestamps
    end
  end
end
