class CreateConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :name, null: false
      t.integer :transport, null: false
      t.jsonb :definition, null: false, default: {}
      t.text :credentials
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :connectors, [ :owner_type, :owner_id, :name ], unique: true
  end
end
