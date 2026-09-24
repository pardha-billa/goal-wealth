# app/services/nav_updates/update_today_nav.rb

require "net/http"
require "json"
require "uri"
require "openssl"
require "bigdecimal/util"

module NavUpdates
  # Daily NAV refresh.
  #
  # Mutual funds: AMFI's NAVAll.txt is the primary source (one request, all
  # schemes, published every business-day evening). mfapi.in is only used to
  # backfill recent history when an asset has gaps, and never overwrites a
  # newer AMFI price with an older one.
  #
  # ETFs: Yahoo Finance chart API.
  class UpdateTodayNav
    AMFI_URL = "https://portal.amfiindia.com/spages/NAVAll.txt"
    MFAPI_URL = "https://api.mfapi.in/mf/%<scheme_code>s"
    YAHOO_URL = "https://%<host>s/v8/finance/chart/%<symbol>s"

    HISTORICAL_NAV_DAYS = 7
    BACKFILL_WINDOW_DAYS = 14

    OPEN_TIMEOUT = 10  # seconds to establish a connection
    READ_TIMEOUT = 45  # seconds to wait for a response chunk
    MAX_RETRY_WAIT = 10

    USER_AGENT = "GoalWealth NAV updater (+https://goal-wealth.onrender.com)".freeze

    def self.call(logger: nil)
      new(logger: logger).call
    end

    def initialize(logger: nil)
      @logger = logger || Logger.new($stdout)
      @errors = []
    end

    def call
      started = Time.current
      amfi = fetch_amfi_rows
      log "AMFI: #{amfi[:by_code].size} schemes, latest NAV date #{amfi[:latest_date] || 'n/a'}"

      updated = 0
      skipped = 0

      Asset.where(active: true, asset_type: %w[mutual_fund etf]).find_each do |asset|
        ok =
          begin
            asset.mutual_fund? ? update_mutual_fund(asset, amfi) : update_etf(asset)
          rescue StandardError => e
            record_error(asset, e)
            false
          end

        ok ? updated += 1 : skipped += 1
        log "#{ok ? 'OK  ' : 'SKIP'} #{asset.asset_type} #{asset.code} #{asset.name}"
      end

      {
        updated: updated,
        skipped: skipped,
        amfi_date: amfi[:latest_date],
        errors: @errors,
        seconds: (Time.current - started).round(1)
      }
    end

    private

    attr_reader :logger

    # ---------- Mutual funds ----------

    def update_mutual_fund(asset, amfi)
      row = amfi[:by_code][asset.code.to_s.strip] ||
            (asset.isin.present? && amfi[:by_isin][asset.isin.strip])

      saved = false
      if row
        save_price(asset, row[:date], row[:price], "AMFI")
        saved = true
      end

      # Only hit mfapi when AMFI had nothing for this asset or recent history has gaps.
      if !saved || needs_backfill?(asset)
        history = fetch_mutual_fund_history(asset)
        history.each { |h| save_price(asset, h[:date], h[:price], "MFAPI") }
        saved ||= history.any?
      end

      saved
    end

    def needs_backfill?(asset)
      asset.price_histories.where("price_date >= ?", BACKFILL_WINDOW_DAYS.days.ago.to_date).count < HISTORICAL_NAV_DAYS
    end

    def fetch_mutual_fund_history(asset)
      scheme_code = asset.code.to_s.strip
      return [] unless scheme_code.match?(/\A\d+\z/)

      response = fetch_response(URI(format(MFAPI_URL, scheme_code: scheme_code)))
      return [] unless response.is_a?(Net::HTTPSuccess)

      rows = Array(JSON.parse(response.body)["data"])
      rows.first(HISTORICAL_NAV_DAYS).filter_map do |row|
        price = row["nav"].to_d
        next if price <= 0

        { date: Date.strptime(row["date"], "%d-%m-%Y"), price: price }
      rescue ArgumentError, TypeError
        nil
      end
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      record_error(asset, e, "mfapi")
      []
    end

    # NAVAll.txt lines look like (8 fields since 2026):
    #   Scheme Code;ISIN Growth;ISIN Reinvest;Scheme Name;Plan;Option;NAV;Date
    # Older files had 6 fields (no Plan/Option). NAV and Date are always the
    # last two fields, so read them from the end to work with both.
    def fetch_amfi_rows
      by_code = {}
      by_isin = {}

      fetch_body(URI(AMFI_URL)).each_line do |line|
        parts = line.strip.split(";").map(&:strip)
        next unless parts.size >= 6 && parts[0].match?(/\A\d+\z/)

        price = parts[-2].to_d
        next unless price.positive?

        date = Date.strptime(parts[-1], "%d-%b-%Y")
        row = { price: price, date: date }
        by_code[parts[0]] = row
        [parts[1], parts[2]].each { |isin| by_isin[isin] = row if isin.match?(/\AIN[A-Z0-9]{10}\z/) }
      rescue ArgumentError, TypeError
        next
      end

      { by_code: by_code, by_isin: by_isin, latest_date: by_code.values.map { |r| r[:date] }.max }
    rescue StandardError => e
      # Don't abort the whole run: mfapi fallback and ETFs can still update.
      @errors << "AMFI: #{e.class}: #{e.message}"
      log "AMFI fetch failed: #{e.class}: #{e.message}"
      { by_code: {}, by_isin: {}, latest_date: nil }
    end

    # ---------- ETFs ----------

    def update_etf(asset)
      code = asset.code.to_s.upcase.strip
      symbol = code.end_with?(".NS", ".BO") ? code : "#{code}.NS"

      response = nil
      %w[query1.finance.yahoo.com query2.finance.yahoo.com].each do |host|
        response = fetch_response(URI(format(YAHOO_URL, host: host, symbol: symbol)))
        break if response.is_a?(Net::HTTPSuccess)
      end
      return false unless response.is_a?(Net::HTTPSuccess)

      meta = JSON.parse(response.body).dig("chart", "result", 0, "meta")
      price = meta&.dig("regularMarketPrice")
      timestamp = meta&.dig("regularMarketTime")
      return false unless price && timestamp

      date = Time.at(timestamp).in_time_zone("Asia/Kolkata").to_date
      save_price(asset, date, price.to_d, "Yahoo Finance")
      true
    end

    # ---------- Persistence ----------

    def save_price(asset, price_date, price, source)
      history = PriceHistory.find_or_initialize_by(asset: asset, price_date: price_date)
      history.price = price
      history.notes = "Source: #{source}"
      history.save! if history.new_record? || history.changed?
    end

    # ---------- HTTP ----------

    def fetch_response(uri, redirects: 5, retries: 2)
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "*/*"

      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        verify_mode: ssl_verify_mode,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(request) }

      case response
      when Net::HTTPTooManyRequests, Net::HTTPServiceUnavailable
        return response unless retries.positive?

        wait = [response["retry-after"].to_i, 2].max.clamp(1, MAX_RETRY_WAIT)
        sleep wait
        fetch_response(uri, redirects: redirects, retries: retries - 1)
      when Net::HTTPRedirection
        raise "Too many redirects for #{uri}" if redirects <= 0
        raise "Redirect without location for #{uri}" unless response["location"]

        fetch_response(URI.join(uri.to_s, response["location"]), redirects: redirects - 1, retries: retries)
      else
        response
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError => e
      raise e unless retries.positive?

      log "Retrying #{uri.host} after #{e.class}"
      sleep 2
      fetch_response(uri, redirects: redirects, retries: retries - 1)
    end

    def fetch_body(uri)
      response = fetch_response(uri)
      return response.body if response.is_a?(Net::HTTPSuccess)

      raise "Failed to fetch #{uri}: #{response.code} #{response.message}"
    end

    # Your Mac's OpenSSL fails CRL checks on some of these hosts, so skip
    # verification only in development. Production/GitHub Actions verify normally.
    def ssl_verify_mode
      Rails.env.development? ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
    end

    def record_error(asset, error, source = nil)
      message = "#{asset.code} #{[source, error.class].compact.join(' ')}: #{error.message}"
      @errors << message
      log "ERROR #{message}"
    end

    def log(message)
      logger.info("[NAV] #{message}")
    end
  end
end
