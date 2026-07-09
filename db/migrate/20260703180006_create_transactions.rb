class CreateTransactions < ActiveRecord::Migration[6.1]
  def change
    create_table :transactions do |t|
      t.references :asset, null: false, foreign_key: true
      t.references :financial_goal, null: false, foreign_key: true
      t.integer :transaction_type, null: false, default: 0
      t.date :transaction_date, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.decimal :nav, precision: 15, scale: 6
      t.text :remarks
      t.timestamps
    end
    add_index :transactions, :transaction_date
  end
end
