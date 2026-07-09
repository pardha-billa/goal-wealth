class CreateFinancialGoals < ActiveRecord::Migration[6.1]
  def change
    create_table :financial_goals do |t|
      t.references :parent_goal, foreign_key: { to_table: :financial_goals }
      t.string :name, null: false
      t.string :code, null: false
      t.decimal :target_amount, precision: 15, scale: 2
      t.date :target_date
      t.integer :status, null: false, default: 0
      t.integer :display_order, null: false, default: 0
      t.text :description
      t.timestamps
    end
    add_index :financial_goals, :code, unique: true
  end
end
