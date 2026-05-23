class AddExternalLoginToConnectorCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :connector_credentials, :external_login, :string
  end
end
