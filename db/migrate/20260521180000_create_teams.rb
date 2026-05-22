class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.string :name, null: false
      t.boolean :personal, null: false, default: false

      t.timestamps
    end
  end
end
