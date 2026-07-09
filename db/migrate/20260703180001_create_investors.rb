class CreateInvestors < ActiveRecord::Migration[6.1]
  def change
    create_table :investors do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :investors, :name, unique: true
  end
end
