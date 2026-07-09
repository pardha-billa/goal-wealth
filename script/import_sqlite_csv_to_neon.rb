require "csv"

tables = %w[
  institutions
  investors
  financial_goals
  investment_accounts
  assets
  transactions
  price_histories
  settings
]

def reset_primary_key_sequence(model)
  pk = model.primary_key
  return unless pk

  sequence_name = ActiveRecord::Base.connection.select_value(
    "SELECT pg_get_serial_sequence(#{ActiveRecord::Base.connection.quote(model.table_name)}, #{ActiveRecord::Base.connection.quote(pk)})"
  )
  return if sequence_name.nil?

  max_id = model.maximum(pk)
  if max_id
    ActiveRecord::Base.connection.execute(
      "SELECT setval(#{ActiveRecord::Base.connection.quote(sequence_name)}, #{max_id}, true)"
    )
  else
    ActiveRecord::Base.connection.execute(
      "SELECT setval(#{ActiveRecord::Base.connection.quote(sequence_name)}, 1, false)"
    )
  end
end

def truncate_import_tables(tables)
  return if tables.empty?

  quoted_tables = tables.map do |table|
    ActiveRecord::Base.connection.quote_table_name(table.classify.constantize.table_name)
  end

  ActiveRecord::Base.connection.execute(
    "TRUNCATE TABLE #{quoted_tables.join(', ')} RESTART IDENTITY CASCADE"
  )
end

import_tables = tables.select do |table|
  File.exist?(Rails.root.join("tmp/sqlite_exports/#{table}.csv"))
end

truncate_import_tables(import_tables)

tables.each do |table|
  path = Rails.root.join("tmp/sqlite_exports/#{table}.csv")
  next unless File.exist?(path)

  puts "Importing #{table}..."

  model = table.classify.constantize

  CSV.foreach(path, headers: true) do |row|
    attrs = row.to_h

    attrs.each do |k, v|
      attrs[k] = nil if v == ""

      if v.present? && v.match?(/\A-?\d+\z/)
        attrs[k] = v.to_i
      end
    end

    id = attrs["id"]
    record = id.present? ? model.find_or_initialize_by(id: id) : model.new
    record.assign_attributes(attrs)
    record.save!
  end

  reset_primary_key_sequence(model)
end

puts "Done."
