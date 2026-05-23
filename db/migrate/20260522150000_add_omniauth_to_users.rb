class AddOmniauthToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string

    # Unique only across users with a provider set; existing
    # password-only users (provider IS NULL) can coexist.
    add_index :users, %i[provider uid], unique: true,
                                        where: "provider IS NOT NULL"
  end
end
