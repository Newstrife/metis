# A pending offer to join a team (docs/tenancy.md). Destroyed to
# revoke; accepted_at is stamped on join and kept for audit. The
# partial unique index allows only one *pending* invite per email per
# team — a re-invite after accept/revoke is fine.
class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :team, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string   :email, null: false
      t.integer  :role, null: false, default: 0
      t.string   :token, null: false
      t.datetime :accepted_at
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, [ :team_id, :email ], unique: true, where: "accepted_at IS NULL"
  end
end
