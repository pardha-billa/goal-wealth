class CreateInvestmentAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :investment_accounts do |t|
      t.references :investor, null: false, foreign_key: true
      t.references :institution, null: false, foreign_key: true
      t.integer :account_type, null: false, default: 0
      t.string :account_number, null: false
      t.string :label
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :investment_accounts, [:investor_id, :institution_id, :account_number], unique: true, name: 'idx_unique_account_per_investor_institution'
  end
end
