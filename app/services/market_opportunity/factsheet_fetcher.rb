require "net/http"
require "pdf-reader"
require "openssl"
require "stringio"
require "yaml"

module MarketOpportunity
  class FactsheetFetcher
    SOURCE_DEFINITIONS = {
      nifty_50: {
        label: "Nifty 50",
        url: "https://www.niftyindices.com/Factsheet/ind_nifty50.pdf"
      },
      nifty_next_50: {
        label: "Nifty Next 50",
        url: "https://www.niftyindices.com/Factsheet/ind_next50.pdf"
      },
      nifty_midcap_150: {
        label: "Nifty Midcap 150",
        url: "https://nsearchives.nseindia.com/content/indices/ind_Nifty_Midcap_150.pdf"
      },
      nifty_smallcap_250: {
        label: "Nifty Smallcap 250",
        url: "https://nsearchives.nseindia.com/content/indices/ind_Nifty_Smallcap_250.pdf"
      }
    }.freeze

    CACHE_TTL = 12.hours

    def call
      source_payload = cached_payload
      {
        as_of: source_payload[:as_of],
        inputs: flattened_inputs(source_payload[:segments]),
        segments: source_payload[:segments],
        sources: SOURCE_DEFINITIONS.transform_values { |definition| definition[:url] }
      }
    end

    private

    def cached_payload
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        build_payload
      end
    rescue StandardError => e
      Rails.logger.warn("[MarketOpportunity::FactsheetFetcher] #{e.class}: #{e.message}")
      build_empty_payload
    end

    def build_payload
      segments = {}
      as_of = nil

      SOURCE_DEFINITIONS.each do |key, definition|
        parsed = parse_source(definition[:url], definition[:label])
        as_of ||= parsed[:as_of]
        segments[key] = parsed
      end

      {
        as_of: as_of,
        segments: segments
      }
    end

    def build_empty_payload
      {
        as_of: nil,
        segments: SOURCE_DEFINITIONS.each_with_object({}) do |(key, definition), memo|
          memo[key] = snapshot_segment(key, definition[:label], definition[:url]).merge(source_state: "unavailable")
        end
      }
    end

    def flattened_inputs(segments)
      segments.each_with_object({}) do |(key, segment), memo|
        prefix = key.to_s
        memo[:"#{prefix}_pe"] = segment[:pe]
        memo[:"#{prefix}_pb"] = segment[:pb]
        memo[:"#{prefix}_dividend_yield"] = segment[:dividend_yield] if segment.key?(:dividend_yield)
        memo[:"#{prefix}_return_1y"] = segment[:return_1y]
        memo[:"#{prefix}_return_3y"] = segment[:return_3y]
        memo[:"#{prefix}_return_5y"] = segment[:return_5y]
      end
    end

    def parse_source(url, label)
      text = pdf_text(download(url))
      {
        key: label_parameter(label),
        label: label,
        source_url: url,
        as_of: parse_as_of(text),
        pe: parse_metric(text, "P/E"),
        pb: parse_metric(text, "P/B"),
        dividend_yield: parse_metric(text, "Dividend Yield"),
        return_1y: parse_return(text, "Total Return", 3),
        return_3y: nil,
        return_5y: parse_return(text, "Total Return", 4),
        source_state: "live"
      }
    rescue StandardError => e
      Rails.logger.warn("[MarketOpportunity::FactsheetFetcher] #{label}: #{e.class}: #{e.message}")
      snapshot_segment(label_parameter(label), label, url).merge(source_state: "snapshot")
    end

    def download(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "Mozilla/5.0"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.request(request)
      end

      raise "Unexpected response: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def pdf_text(binary)
      reader = PDF::Reader.new(StringIO.new(binary))
      reader.pages.map(&:text).join("\n")
    end

    def parse_as_of(text)
      first_line = text.lines.find { |line| line.match?(/\A[A-Za-z]+\s+\d{1,2},\s+\d{4}\z/) }
      first_line.to_s.strip.presence
    end

    def parse_metric(text, label)
      line = text.lines.find { |candidate| candidate.include?(label) }
      return nil unless line

      match = line.scan(/-?\d+(?:\.\d+)?/).last
      match&.to_d
    end

    def parse_return(text, row_label, value_index)
      line = text.lines.find { |candidate| candidate.lstrip.match?(/\A#{Regexp.escape(row_label)}\b/) }
      return nil unless line

      values = line.scan(/-?\d+(?:\.\d+)?/).map(&:to_d)
      values[value_index]
    end

    def label_parameter(label)
      label.downcase.tr(" ", "_").to_sym
    end

    def cache_key
      "market-opportunity:factsheet-fetcher:v2"
    end

    def snapshot_segment(key, label, url)
      snapshot = snapshot_payload.fetch(:segments, {}).fetch(key.to_sym, {})
      {
        key: key,
        label: label,
        source_url: url,
        as_of: snapshot[:as_of] || snapshot_payload[:as_of],
        pe: snapshot[:pe],
        pb: snapshot[:pb],
        dividend_yield: snapshot[:dividend_yield],
        return_1y: snapshot[:return_1y],
        return_3y: snapshot[:return_3y],
        return_5y: snapshot[:return_5y]
      }
    end

    def snapshot_payload
      @snapshot_payload ||= YAML.load_file(Rails.root.join("app/services/market_opportunity/source_snapshots/latest_factsheets.yml")).deep_symbolize_keys
    end
  end
end
