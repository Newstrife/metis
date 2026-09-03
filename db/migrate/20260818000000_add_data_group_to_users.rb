class AddDataGroupToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :data_group, :integer, default: 0, null: false

    # 默认最小权限：所有人（含企微自动注册的成员）一律 general；
    # 仅超管预设为 full，其余由超管在用户管理页按需提权。
    User.where(superuser: true).update_all(data_group: 4)
  end

  def down
    remove_column :users, :data_group
  end
end
