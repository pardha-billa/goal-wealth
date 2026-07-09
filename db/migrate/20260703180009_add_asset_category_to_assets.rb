class AddAssetCategoryToAssets < ActiveRecord::Migration[6.1]
  def change
      add_column :assets, :asset_category, :integer, null: false, default: 0
    add_index :assets, :asset_category
  end
end
