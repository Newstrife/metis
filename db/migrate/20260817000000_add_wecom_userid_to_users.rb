class AddWecomUseridToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :wecom_userid, :string
    add_index :users, :wecom_userid, unique: true
  end
end
