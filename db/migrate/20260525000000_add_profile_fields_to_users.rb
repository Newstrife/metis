class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :display_name
      t.string :timezone
      t.string :language
      t.string :preferred_model
    end
  end
end
