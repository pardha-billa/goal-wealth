class DeviseCreateUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :users do |t|
      t.string :email, null: false, default: ''
      t.string :password_digest, null: false, default: ''
      t.boolean :admin, null: false, default: false

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
  end
end
