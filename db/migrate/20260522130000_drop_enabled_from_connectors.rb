class DropEnabledFromConnectors < ActiveRecord::Migration[8.1]
  def change
    remove_column :connectors, :enabled, :boolean, default: true, null: false
  end
end
