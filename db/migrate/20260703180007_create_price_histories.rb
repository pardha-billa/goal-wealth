class CreatePriceHistories < ActiveRecord::Migration[6.1]
  def change
    create_table :price_histories do |t|
      t.references :asset, null: false, foreign_key: true
      t.date :price_date, null: false
      t.decimal :price, precision: 15, scale: 6, null: false
      t.text :notes
      t.timestamps
    end
    add_index :price_histories, [:asset_id, :price_date], unique: true
  end
end
