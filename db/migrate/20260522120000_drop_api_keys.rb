class DropApiKeys < ActiveRecord::Migration[8.1]
  def change
    drop_table :api_keys do |t|
      t.references :user, null: false
      t.string :provider, null: false
      t.text :key, null: false
      t.timestamps
      t.index [ :user_id, :provider ], unique: true
    end
  end
end
