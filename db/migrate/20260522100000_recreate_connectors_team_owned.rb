class RecreateConnectorsTeamOwned < ActiveRecord::Migration[8.1]
  # connectors was created polymorphic-owned with an inline credentials
  # column (the pre-tenancy design). It carries no production data, so
  # recreate it team-owned — credentials move to connector_credentials.
  def up
    drop_table :connectors

    create_table :connectors do |t|
      t.references :team, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :transport, null: false
      t.jsonb :definition, null: false, default: {}
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :connectors, [ :team_id, :name ], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
