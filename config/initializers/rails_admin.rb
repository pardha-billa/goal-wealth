RailsAdmin.config do |config|
  config.asset_source = :sprockets

  config.actions do
    dashboard
    index
    new
    export
    bulk_delete
    show
    edit
    delete
    show_in_app
  end

  config.model 'Investor' do
    navigation_label 'Master Data'
    list do
      field :name
      field :email
      field :phone
      field :active
    end
    edit do
      field :name
      field :email
      field :phone
      field :notes
      field :active
    end
  end

  config.model 'Institution' do
    navigation_label 'Master Data'
    list do
      field :name
      field :institution_type
      field :website
      field :active
    end
    edit do
      field :name
      field :institution_type, :enum do
        enum { Institution.institution_types }
      end
      field :website
      field :notes
      field :active
    end
  end

  config.model 'InvestmentAccount' do
    navigation_label 'Master Data'
    object_label_method :display_name
    list do
      field :investor
      field :institution
      field :account_type
      field :account_number
      field :label
      field :active
    end
    edit do
      field :investor
      field :institution
      field :account_type, :enum do
        enum { InvestmentAccount.account_types }
      end

      field :account_number
      field :label do
        help 'Friendly account name such as Main MF, Emergency, Trading, or PPF.'
      end
      field :notes
      field :active
    end
  end

  config.model 'Asset' do
    navigation_label 'Portfolio Setup'
    object_label_method :to_s
    list do
      field :investment_account
      field :asset_type
      field :code
      field :name
      field :plan
      field :option
      field :active
    end
    edit do
      field :investment_account do
        help 'The asset belongs to this folio/demat/PPF account. Investor and institution are derived from the account.'
      end
      field :asset_type, :enum do
        enum { Asset.asset_types }
      end
      field :asset_category, :enum do
        enum { Asset.asset_categories }
      end
      field :code do
        help 'AMFI scheme code for mutual funds, symbol for ETF/stocks, or PPF/EPF/NPS code.'
      end
      field :name do
        help 'Your display name, e.g. PPFCF or NIFTYBEES.'
      end
      field :official_name
      field :plan, :enum do
        enum { Asset.plans }
      end
      field :option, :enum do
        enum { Asset.options }
      end
      field :isin
      field :notes
      field :active
    end
  end

  config.model 'FinancialGoal' do
    navigation_label 'Planning'
    object_label_method :to_s
    list do
      field :code
      field :name
      field :parent_goal
      field :target_amount
      field :target_date
      field :status
      field :display_order
    end
    edit do
      field :parent_goal
      field :name
      field :code do
        help 'Short unique code used in reports/imports, e.g. RET, PRET, SEDU.'
      end
      field :target_amount
      field :target_date
      field :status, :enum do
        enum { FinancialGoal.statuses }
      end
      field :display_order
      field :description
    end
  end

  config.model 'Transaction' do
    navigation_label 'Transactions'
    object_label_method :to_s
    list do
      field :transaction_date
      field :transaction_type
      field :asset
      field :financial_goal
      field :amount
      field :nav
    end
    edit do
      field :asset do
        help 'Only Asset is selected. Investor, institution, and account are derived from the asset.'
      end
      field :financial_goal do
        help 'Purpose of the transaction. Can be corrected later.'
      end
      field :transaction_type, :enum do
        enum { Transaction.transaction_types }
      end
      field :transaction_date
      field :amount
      field :nav do
        help 'NAV/price. Units are calculated as amount / nav when nav is present.'
      end
      field :remarks
    end
  end

  config.model 'PriceHistory' do
    navigation_label 'Valuation'
    list do
      scopes [:latest_first, :last_trading_days]
      field :asset do
        searchable %i[name code]
      end
      field :price_date
      field :price
    end
    edit do
      field :asset
      field :price_date
      field :price
      field :notes
    end
  end

  config.model 'Setting' do
    navigation_label 'System'
    edit do
      field :key
      field :value
    end
  end
end
