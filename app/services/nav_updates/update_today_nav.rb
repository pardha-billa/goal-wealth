# app/services/nav_updates/update_today_nav.rb

require "net/http"
require "json"
require "uri"
require "openssl"

module NavUpdates
  class UpdateTodayNav
    AMFI_URL = "https://www.amfiindia.com/spages/NAVAll.txt"
    MFAPI_URL = "https://api.mfapi.in/mf/%<scheme_code>s"
    HISTORICAL_NAV_DAYS = 7
    # Some remote NAV endpoints fail OpenSSL CRL verification in local environments.
    # We disable SSL verification for these external data fetches.
    SSL_VERIFY_MODE = OpenSSL::SSL::VERIFY_NONE

    def self.call
      new.call
    end

    def call
      mf_rows = fetch_amfi_rows

      updated = 0
      skipped = 0

      Asset.where(active: true).find_each do |asset|
        result =
          case asset.asset_type
          when "mutual_fund"
            update_mutual_fund(asset, mf_rows)
          when "etf"
            update_etf(asset)
          else
            false
          end

        result ? updated += 1 : skipped += 1
      end

      { updated: updated, skipped: skipped }
    end

    private

    def update_mutual_fund(asset, mf_rows)
      history_rows = fetch_mutual_fund_history(asset)
      return save_amfi_snapshot(asset, mf_rows) if history_rows.empty?

      history_rows.each do |row|
        save_price(asset, row[:date], row[:price], "MFAPI")
      end

      true
    end

    def save_amfi_snapshot(asset, mf_rows)
      row = mf_rows[asset.code.to_s]
      return false unless row

      save_price(asset, row[:date], row[:price], "AMFI")
      true
    end

    def update_etf(asset)
      symbol = asset.code.to_s.upcase.end_with?(".NS") ? asset.code.to_s.upcase : "#{asset.code.to_s.upcase}.NS"
      url = URI("https://query1.finance.yahoo.com/v8/finance/chart/#{symbol}")

      response = fetch_response(url)
      unless response.is_a?(Net::HTTPSuccess)
        alt_url = URI(url.to_s.sub("query1.finance.yahoo.com", "query2.finance.yahoo.com"))
        response = fetch_response(alt_url)
      end
      return false unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      result = json.dig("chart", "result", 0)
      return false unless result

      price = result.dig("meta", "regularMarketPrice")
      timestamp = result.dig("meta", "regularMarketTime")
      return false unless price && timestamp

      price_date = Time.at(timestamp).to_date

      save_price(asset, price_date, price, "Yahoo Finance")
      true
    end

    def fetch_mutual_fund_history(asset)
      scheme_code = asset.code.to_s.strip
      return [] unless scheme_code.match?(/\A\d+\z/)

      response = fetch_response(URI(format(MFAPI_URL, scheme_code: scheme_code)))
      return [] unless response.is_a?(Net::HTTPSuccess)

      json = JSON.parse(response.body)
      rows = Array(json["data"])

      rows.first(HISTORICAL_NAV_DAYS).filter_map do |row|
        date = Date.strptime(row["date"], "%d-%m-%Y")
        price = row["nav"].to_d
        next if price <= 0

        { date: date, price: price }
      rescue ArgumentError, TypeError
        nil
      end
    rescue JSON::ParserError, StandardError
      []
    end

    def save_price(asset, price_date, price, source)
      PriceHistory.find_or_initialize_by(
        asset: asset,
        price_date: price_date
      ).tap do |history|
        history.price = price
        history.notes = "Source: #{source}"
        history.save!
      end
    end

    def fetch_amfi_rows
      text = fetch_body(URI(AMFI_URL))
      rows = {}

      text.each_line do |line|
        parts = line.strip.split(";")
        next unless parts.size >= 6
        next unless parts[0].to_s.match?(/\A\d+\z/)

        rows[parts[0]] = {
          price: parts[4].to_d,
          date: Date.strptime(parts[5], "%d-%b-%Y")
        }
      rescue
        next
      end

      rows
    end

    def fetch_response(uri, redirects = 5, retries = 3)
      uri = URI(uri) unless uri.is_a?(URI)
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
      request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
      request['Accept-Language'] = 'en-US,en;q=0.9'
      request['Cache-Control'] = 'no-cache'
      request['Pragma'] = 'no-cache'
      request['Connection'] = 'close'

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", verify_mode: SSL_VERIFY_MODE) do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPTooManyRequests) && retries.positive?
        retry_after = response['retry-after']&.to_i
        wait = retry_after && retry_after > 0 ? retry_after : (2**(4 - retries))
        sleep wait
        return fetch_response(uri, redirects, retries - 1)
      end

      if response.is_a?(Net::HTTPRedirection)
        raise "Too many redirects" if redirects <= 0

        location = response['location']
        raise "Redirect without location" unless location

        fetch_response(URI.join(uri, location), redirects - 1, retries)
      else
        response
      end
    end

    def fetch_body(uri)
      response = fetch_response(uri)
      return response.body if response.is_a?(Net::HTTPSuccess)

      raise "Failed to fetch #{uri}: #{response.code} #{response.message}"
    end
  end
end
