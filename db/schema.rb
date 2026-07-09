# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_07_03_180009) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "assets", force: :cascade do |t|
    t.bigint "investment_account_id", null: false
    t.integer "asset_type", default: 0, null: false
    t.string "code", null: false
    t.string "name", null: false
    t.string "official_name"
    t.integer "plan"
    t.integer "option"
    t.string "isin"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "asset_category", default: 0, null: false
    t.index ["asset_category"], name: "index_assets_on_asset_category"
    t.index ["investment_account_id", "asset_type", "code"], name: "idx_unique_asset_per_account_type_code", unique: true
    t.index ["investment_account_id"], name: "index_assets_on_investment_account_id"
  end

  create_table "financial_goals", force: :cascade do |t|
    t.bigint "parent_goal_id"
    t.string "name", null: false
    t.string "code", null: false
    t.decimal "target_amount", precision: 15, scale: 2
    t.date "target_date"
    t.integer "status", default: 0, null: false
    t.integer "display_order", default: 0, null: false
    t.text "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["code"], name: "index_financial_goals_on_code", unique: true
    t.index ["parent_goal_id"], name: "index_financial_goals_on_parent_goal_id"
  end

  create_table "institutions", force: :cascade do |t|
    t.string "name", null: false
    t.integer "institution_type", default: 0, null: false
    t.string "website"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_institutions_on_name", unique: true
  end

  create_table "investment_accounts", force: :cascade do |t|
    t.bigint "investor_id", null: false
    t.bigint "institution_id", null: false
    t.integer "account_type", default: 0, null: false
    t.string "account_number", null: false
    t.string "label"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["institution_id"], name: "index_investment_accounts_on_institution_id"
    t.index ["investor_id", "institution_id", "account_number"], name: "idx_unique_account_per_investor_institution", unique: true
    t.index ["investor_id"], name: "index_investment_accounts_on_investor_id"
  end

  create_table "investors", force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_investors_on_name", unique: true
  end

  create_table "price_histories", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.date "price_date", null: false
    t.decimal "price", precision: 15, scale: 6, null: false
    t.text "notes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["asset_id", "price_date"], name: "index_price_histories_on_asset_id_and_price_date", unique: true
    t.index ["asset_id"], name: "index_price_histories_on_asset_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.bigint "financial_goal_id", null: false
    t.integer "transaction_type", default: 0, null: false
    t.date "transaction_date", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.decimal "nav", precision: 15, scale: 6
    t.text "remarks"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["asset_id"], name: "index_transactions_on_asset_id"
    t.index ["financial_goal_id"], name: "index_transactions_on_financial_goal_id"
    t.index ["transaction_date"], name: "index_transactions_on_transaction_date"
  end

  add_foreign_key "assets", "investment_accounts"
  add_foreign_key "financial_goals", "financial_goals", column: "parent_goal_id"
  add_foreign_key "investment_accounts", "institutions"
  add_foreign_key "investment_accounts", "investors"
  add_foreign_key "price_histories", "assets"
  add_foreign_key "transactions", "assets"
  add_foreign_key "transactions", "financial_goals"
end
