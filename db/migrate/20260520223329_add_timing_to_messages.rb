class AddTimingToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :started_at, :datetime
    add_column :messages, :finished_at, :datetime
  end
end
