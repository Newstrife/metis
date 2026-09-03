class CreateRbacDataPermissions < ActiveRecord::Migration[8.1]
  def change
    # 角色：可自由新增，full_access 角色不受目录限制（超管/运维）
    create_table :roles do |t|
      t.string :name, null: false
      t.string :description
      t.boolean :full_access, null: false, default: false
      t.timestamps
      t.index :name, unique: true
    end

    # 人 ↔ 角色：一个人可挂多个角色
    create_table :role_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.timestamps
      t.index %i[user_id role_id], unique: true
    end

    # 数据目录：知识库根目录下的一个子目录 = 一个权限单元，可新增可配置
    create_table :data_directories do |t|
      t.string :name, null: false
      t.string :path, null: false
      t.string :description
      t.boolean :public_access, null: false, default: false
      t.timestamps
      t.index :path, unique: true
    end

    # 角色 ↔ 目录：角色的权限清单
    create_table :directory_grants do |t|
      t.references :role, null: false, foreign_key: true
      t.references :data_directory, null: false, foreign_key: true
      t.timestamps
      t.index %i[role_id data_directory_id], unique: true
    end

    # 从固定枚举过渡：超管获得「全部数据」角色；初始目录对应
    # E:\enterprise_data 的现有子目录结构（考勤制度默认全员可见）。
    full = Role.create!(name: "全部数据", description: "不受目录权限限制（超管/运维）", full_access: true)
    User.where(superuser: true).find_each { |u| u.role_assignments.create!(role: full) }

    DataDirectory.create!(name: "考勤制度", path: "考勤制度", description: "考勤及假期管理制度", public_access: true)
    DataDirectory.create!(name: "设备监测", path: "设备监测", description: "生产设备及公用系统每日运行监测记录")
    DataDirectory.create!(name: "员工名册", path: "员工名册", description: "在职员工与组织信息（摄取时已脱敏）")
    DataDirectory.create!(name: "流程数据", path: "流程数据", description: "流程发起情况等业务数据")

    remove_column :users, :data_group, :integer, default: 0, null: false
  end
end
