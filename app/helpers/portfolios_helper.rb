module PortfoliosHelper
  def indian_currency(amount, show_symbol: true)
    return '—' if amount.nil?

    integer_amount = amount.to_i
    negative = integer_amount.negative?
    num_str = integer_amount.abs.to_s
    
    if num_str.length <= 3
      formatted = num_str
    else
      digits = num_str.split('')
      groups = []
      
      # Group from right: first group has 3 digits, rest have 2
      while digits.length > 0
        if groups.empty?
          # First group: take up to 3 digits from the right
          group_size = [3, digits.length].min
          groups.unshift(digits.pop(group_size).join(''))
        else
          # Subsequent groups: take 2 digits
          group_size = [2, digits.length].min
          groups.unshift(digits.pop(group_size).join(''))
        end
      end
      
      formatted = groups.join(',')
    end
    
    formatted = show_symbol ? "₹#{formatted}" : formatted
    negative ? "-#{formatted}" : formatted
  end

  def portfolio_percent(value, precision: 2)
    return '—' if value.nil?

    "#{number_with_precision(value, precision: precision, strip_insignificant_zeros: true)}%"
  end

  def compact_indian_currency(amount)
    return '—' if amount.nil?

    value = amount.to_d
    sign = value.negative? ? '-' : ''
    absolute_value = value.abs

    scaled_value, suffix =
      if absolute_value >= 1_00_00_000
        [absolute_value / 1_00_00_000, 'Cr']
      elsif absolute_value >= 1_00_000
        [absolute_value / 1_00_000, 'L']
      elsif absolute_value >= 1_000
        [absolute_value / 1_000, 'K']
      else
        [absolute_value, '']
      end

    precision = scaled_value >= 10 || suffix.blank? ? 1 : 2
    formatted_value = number_with_precision(scaled_value, precision: precision, strip_insignificant_zeros: true)
    "#{sign}₹#{formatted_value}#{suffix}"
  end

  def portfolio_trend_class(value, positive: 'success', negative: 'danger', neutral: '500')
    return neutral if value.nil?

    value.to_d >= 0 ? positive : negative
  end

  def portfolio_trend_icon(value)
    return nil if value.nil?

    value.to_d >= 0 ? 'up' : 'down'
  end
end
