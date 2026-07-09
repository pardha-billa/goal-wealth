class CreateAssets < ActiveRecord::Migration[6.1]
  def change
    create_table :assets do |t|
      t.references :investment_account, null: false, foreign_key: true
      t.integer :asset_type, null: false, default: 0
      t.string :code, null: false
      t.string :name, null: false
      t.string :official_name
      t.integer :plan
      t.integer :option
      t.string :isin
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :assets, [:investment_account_id, :asset_type, :code], unique: true, name: 'idx_unique_asset_per_account_type_code'
  end
end
