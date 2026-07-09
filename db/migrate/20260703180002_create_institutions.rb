class CreateInstitutions < ActiveRecord::Migration[6.1]
  def change
    create_table :institutions do |t|
      t.string :name, null: false
      t.integer :institution_type, null: false, default: 0
      t.string :website
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :institutions, :name, unique: true
  end
end
