class AddPersonalizationToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.text :about_you
      t.text :custom_instructions
      t.string :theme
    end
  end
end
