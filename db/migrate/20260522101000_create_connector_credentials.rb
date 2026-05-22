class CreateConnectorCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :connector_credentials do |t|
      t.references :connector, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text :credentials

      t.timestamps
    end

    # One shared credential (user_id NULL) plus one per member, per
    # connector — NULLs compared as equal so the shared row stays unique.
    add_index :connector_credentials, [ :connector_id, :user_id ],
              unique: true, nulls_not_distinct: true
  end
end
