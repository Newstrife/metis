class CreateIdentities < ActiveRecord::Migration[8.1]
  # A user's OAuth identity at an external provider. Replaces the
  # scalar `provider`/`uid` columns on `users` so a user can hold
  # several identities at once (GitHub + Google + …) — required for
  # Google sign-in to coexist with GitHub on the same account, and for
  # one operator to authorize multiple identity-bearing connectors.
  # See docs/connectors.md.
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
    end
    add_index :identities, [ :provider, :uid ], unique: true

    # Backfill from the legacy scalar columns. A user with a non-null
    # provider had exactly one identity; carry it across.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          INSERT INTO identities (user_id, provider, uid, created_at, updated_at)
          SELECT id, provider, uid, NOW(), NOW()
          FROM users
          WHERE provider IS NOT NULL AND uid IS NOT NULL
        SQL
      end
    end

    remove_index :users, name: "index_users_on_provider_and_uid", if_exists: true
    remove_column :users, :provider, :string
    remove_column :users, :uid, :string
  end
end
