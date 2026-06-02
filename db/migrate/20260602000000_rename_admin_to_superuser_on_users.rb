class RenameAdminToSuperuserOnUsers < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :admin, :superuser
  end
end
