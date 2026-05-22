class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :conversations, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :connectors, as: :owner, dependent: :destroy

  def api_key_for(provider)
    api_keys.find_by(provider: provider.to_s)&.key
  end
end
