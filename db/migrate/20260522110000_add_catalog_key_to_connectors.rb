class AddCatalogKeyToConnectors < ActiveRecord::Migration[8.1]
  def change
    # The marketplace app a connector was created from; null for a
    # custom connector. A team connects a given app at most once.
    add_column :connectors, :catalog_key, :string
    add_index :connectors, [ :team_id, :catalog_key ], unique: true
  end
end
