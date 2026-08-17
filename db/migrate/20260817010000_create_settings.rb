class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings, id: false do |t|
      t.string :key, null: false
      t.jsonb :value
      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
