class DropExamplesFromSkills < ActiveRecord::Migration[8.1]
  def change
    remove_column :skills, :examples, :jsonb, default: [], null: false
  end
end
