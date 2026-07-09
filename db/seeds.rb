# Seed default institutions only. Add investors, accounts, assets, goals and transactions in RailsAdmin.
[
  ['HDFC AMC', :amc],
  ['ICICI AMC', :amc],
  ['SBI AMC', :amc],
  ['Nippon India AMC', :amc],
  ['PPFAS AMC', :amc],
  ['Upstox', :broker],
  ['Groww', :broker],
  ['Zerodha', :broker],
  ['India Post', :government],
  ['EPFO', :retirement]
].each do |name, type|
  Institution.find_or_create_by!(name: name) do |institution|
    institution.institution_type = type
    institution.active = true
  end
end

Setting.find_or_create_by!(key: 'currency') { |setting| setting.value = 'INR' }
