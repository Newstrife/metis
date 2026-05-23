# A per-(user, provider) OAuth grant — one row per Google/GitHub
# account a user has authorized for any purpose. The actual access and
# refresh tokens live here (encrypted), keyed by provider rather than
# by connector, so a single OAuth handshake covers every connector
# whose scopes are subsets of the grant. See docs/connectors.md.
class CreateOauthGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.text :access_token   # encrypted (ActiveRecord encrypts)
      t.text :refresh_token  # encrypted
      t.datetime :expires_at
      t.text :scopes         # space-separated, e.g. "email profile gmail.readonly"

      t.timestamps
    end

    # One grant per user per provider — the OAuth flow always upserts
    # the same row, adding scopes incrementally.
    add_index :oauth_grants, [ :user_id, :provider ], unique: true
  end
end
