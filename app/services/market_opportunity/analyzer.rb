require "json"

module MarketOpportunity
  class Analyzer
    PARAM_KEYS = %i[
      nifty_50_pe
      nifty_50_pb
      nifty_50_dividend_yield
      nifty_50_hist_pe_percentile
      nifty_50_return_1y
      nifty_50_return_3y
      nifty_50_return_5y
      nifty_50_earnings_growth
      nifty_next_50_pe
      nifty_next_50_pb
      nifty_next_50_hist_pe_percentile
      nifty_next_50_return_1y
      nifty_next_50_return_3y
      nifty_next_50_return_5y
      nifty_next_50_earnings_growth
      nifty_midcap_150_pe
      nifty_midcap_150_pb
      nifty_midcap_150_hist_pe_percentile
      nifty_midcap_150_return_1y
      nifty_midcap_150_return_3y
      nifty_midcap_150_return_5y
      nifty_midcap_150_earnings_growth
      nifty_smallcap_250_pe
      nifty_smallcap_250_pb
      nifty_smallcap_250_hist_pe_percentile
      nifty_smallcap_250_return_1y
      nifty_smallcap_250_return_3y
      nifty_smallcap_250_return_5y
      nifty_smallcap_250_earnings_growth
      market_breadth
      rbi_policy_direction
      major_earnings_trend
      investment_horizon_years
      emergency_fund_available
      near_term_cash_requirement
      current_equity_allocation_pct
      target_equity_allocation_pct
      segment_concentration_pct
      fall_tolerance_pct
      upcoming_obligations
      flow_signal
    ].freeze

    SEGMENTS = {
      nifty_50: {
        label: "Nifty 50",
        risk_base: 28,
        source: :direct,
        pe_key: :nifty_50_pe,
        pb_key: :nifty_50_pb,
        dividend_key: :nifty_50_dividend_yield,
        percentile_key: :nifty_50_hist_pe_percentile,
        return_keys: %i[nifty_50_return_1y nifty_50_return_3y nifty_50_return_5y],
        earnings_key: :nifty_50_earnings_growth
      },
      nifty_next_50: {
        label: "Nifty Next 50",
        risk_base: 42,
        source: :direct,
        pe_key: :nifty_next_50_pe,
        pb_key: :nifty_next_50_pb,
        dividend_key: :nifty_next_50_dividend_yield,
        percentile_key: :nifty_next_50_hist_pe_percentile,
        return_keys: %i[nifty_next_50_return_1y nifty_next_50_return_3y nifty_next_50_return_5y],
        earnings_key: :nifty_next_50_earnings_growth
      },
      large_cap: {
        label: "Large-cap segment",
        risk_base: 34,
        source: :derived,
        derived_from: %i[nifty_50 nifty_next_50]
      },
      mid_cap: {
        label: "Mid-cap segment",
        risk_base: 62,
        source: :direct,
        pe_key: :nifty_midcap_150_pe,
        pb_key: :nifty_midcap_150_pb,
        dividend_key: :nifty_midcap_150_dividend_yield,
        percentile_key: :nifty_midcap_150_hist_pe_percentile,
        return_keys: %i[nifty_midcap_150_return_1y nifty_midcap_150_return_3y nifty_midcap_150_return_5y],
        earnings_key: :nifty_midcap_150_earnings_growth
      },
      small_cap: {
        label: "Small-cap segment",
        risk_base: 78,
        source: :direct,
        pe_key: :nifty_smallcap_250_pe,
        pb_key: :nifty_smallcap_250_pb,
        dividend_key: :nifty_smallcap_250_dividend_yield,
        percentile_key: :nifty_smallcap_250_hist_pe_percentile,
        return_keys: %i[nifty_smallcap_250_return_1y nifty_smallcap_250_return_3y nifty_smallcap_250_return_5y],
        earnings_key: :nifty_smallcap_250_earnings_growth
      }
    }.freeze

    PERSONAL_KEYS = %i[
      investment_horizon_years
      emergency_fund_available
      near_term_cash_requirement
      current_equity_allocation_pct
      target_equity_allocation_pct
      segment_concentration_pct
      fall_tolerance_pct
      upcoming_obligations
    ].freeze

    MARKET_KEYS = PARAM_KEYS - PERSONAL_KEYS

    def initialize(params = {}, client: nil, factsheet_fetcher: nil)
      @params = params.to_h.deep_symbolize_keys
      @client = client || openai_client
      @factsheet_fetcher = factsheet_fetcher || MarketOpportunity::FactsheetFetcher.new
    end

    def call
      source_data = source_inputs
      input = normalized_inputs(source_data)
      segments = build_segments(input)
      ranked_segments = segments.values.sort_by do |segment|
        score = segment[:score].present? ? segment[:score].to_d : 0
        [-score, segment[:key].to_s]
      end
      overall = build_overall(segments, ranked_segments, source_data)
      checklist = build_checklist(input, overall, ranked_segments)
      deployment = build_deployment(ranked_segments, checklist, overall)
      narrative = build_narrative(input, segments, overall, checklist, deployment)

      {
        inputs: input,
        sources: source_data,
        segments: segments,
        ranked_segments: ranked_segments,
        overall: overall.merge(narrative),
        checklist: checklist,
        deployment: deployment
      }
    end

    private

    def source_inputs
      @source_inputs ||= begin
        payload = @factsheet_fetcher.call
        payload.fetch(:inputs, {}).merge(
          market_breadth: nil,
          rbi_policy_direction: nil,
          major_earnings_trend: nil,
          flow_signal: nil,
          investment_horizon_years: nil,
          emergency_fund_available: nil,
          near_term_cash_requirement: nil,
          current_equity_allocation_pct: nil,
          target_equity_allocation_pct: nil,
          segment_concentration_pct: nil,
          fall_tolerance_pct: nil,
          upcoming_obligations: nil
        ).merge(
          source_as_of: payload[:as_of],
          source_segments: payload[:segments],
          source_urls: payload[:sources]
        )
      end
    end

    def normalized_inputs(source_data)
      input = source_data.dup

      PARAM_KEYS.each do |key|
        next unless @params.key?(key) || @params.key?(key.to_s)

        raw_value = @params.key?(key) ? @params[key] : @params[key.to_s]
        next if raw_value.blank?

        input[key] = normalize_value(key, raw_value)
      end

      input
    end

    def normalize_value(key, value)
      case key
      when :emergency_fund_available, :near_term_cash_requirement, :upcoming_obligations
        cast_boolean(value)
      when :rbi_policy_direction, :major_earnings_trend, :flow_signal
        value.to_s.strip.presence
      when :investment_horizon_years, :current_equity_allocation_pct, :target_equity_allocation_pct,
           :segment_concentration_pct, :fall_tolerance_pct, :market_breadth,
           :nifty_50_hist_pe_percentile, :nifty_next_50_hist_pe_percentile,
           :nifty_midcap_150_hist_pe_percentile, :nifty_smallcap_250_hist_pe_percentile
        value.to_s.tr(",", "").to_d
      else
        value.to_s.tr(",", "").to_d
      end
    end

    def cast_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def build_segments(input)
      direct_segments = {}

      SEGMENTS.each do |key, config|
        next unless config[:source] == :direct

        direct_segments[key] = direct_segment(key, config, input)
      end

      SEGMENTS.each_with_object(direct_segments.dup) do |(key, config), memo|
        next unless config[:source] == :derived

        memo[key] = derived_segment(key, config, direct_segments, input)
      end
    end

    def direct_segment(key, config, input)
      pe = input[config[:pe_key]]
      pb = input[config[:pb_key]]
      dividend = config[:dividend_key] ? input[config[:dividend_key]] : nil
      percentile = input[config[:percentile_key]]
      returns = config[:return_keys].map { |return_key| input[return_key] }
      earnings_growth = input[config[:earnings_key]]

      valuation = valuation_score(pe, pb, percentile, dividend)
      earnings = earnings_score(earnings_growth, input[:major_earnings_trend])
      momentum = momentum_score(returns)
      breadth = breadth_score(input[:market_breadth])
      drawdown = drawdown_score(config[:risk_base], percentile, returns, valuation)
      flow = flow_score(input[:flow_signal], config[:risk_base])

      score = opportunity_score(
        valuation: valuation,
        earnings: earnings,
        momentum: momentum,
        breadth: breadth,
        drawdown: drawdown,
        flow: flow
      )

      {
        key: key,
        label: config[:label],
        pe: pe,
        pb: pb,
        dividend_yield: dividend,
        historical_pe_percentile: percentile,
        return_1y: returns[0],
        return_3y: returns[1],
        return_5y: returns[2],
        earnings_growth: earnings_growth,
        valuation_score: valuation,
        earnings_score: earnings,
        momentum_score: momentum,
        breadth_score: breadth,
        drawdown_score: drawdown,
        flow_score: flow,
        score: score,
        valuation_label: valuation_label(percentile, pe, pb),
        earnings_label: earnings_label(earnings_growth),
        risk_label: risk_label(config[:risk_base], percentile),
        lumpsum_view: lumpsum_view(score, config[:risk_base]),
        commentary: segment_commentary(config[:label])
      }
    end

    def derived_segment(key, config, direct_segments, input)
      sources = config[:derived_from].map { |source_key| direct_segments[source_key] }
      blended_pe = weighted_average(sources.map { |segment| segment[:pe] }, [0.55, 0.45])
      blended_pb = weighted_average(sources.map { |segment| segment[:pb] }, [0.55, 0.45])
      blended_percentile = weighted_average(sources.map { |segment| segment[:historical_pe_percentile] }, [0.55, 0.45])
      blended_dividend = weighted_average(sources.map { |segment| segment[:dividend_yield] }, [0.55, 0.45])
      blended_returns = [
        weighted_average(sources.map { |segment| segment[:return_1y] }, [0.55, 0.45]),
        weighted_average(sources.map { |segment| segment[:return_3y] }, [0.55, 0.45]),
        weighted_average(sources.map { |segment| segment[:return_5y] }, [0.55, 0.45])
      ]
      blended_earnings = weighted_average(sources.map { |segment| segment[:earnings_growth] }, [0.55, 0.45])

      valuation = valuation_score(blended_pe, blended_pb, blended_percentile, blended_dividend)
      earnings = earnings_score(blended_earnings, input[:major_earnings_trend])
      momentum = momentum_score(blended_returns)
      breadth = breadth_score(input[:market_breadth])
      drawdown = drawdown_score(config[:risk_base], blended_percentile, blended_returns, valuation)
      flow = flow_score(input[:flow_signal], config[:risk_base])

      score = opportunity_score(
        valuation: valuation,
        earnings: earnings,
        momentum: momentum,
        breadth: breadth,
        drawdown: drawdown,
        flow: flow
      )

      {
        key: key,
        label: config[:label],
        pe: blended_pe,
        pb: blended_pb,
        dividend_yield: blended_dividend,
        historical_pe_percentile: blended_percentile,
        return_1y: blended_returns[0],
        return_3y: blended_returns[1],
        return_5y: blended_returns[2],
        earnings_growth: blended_earnings,
        valuation_score: valuation,
        earnings_score: earnings,
        momentum_score: momentum,
        breadth_score: breadth,
        drawdown_score: drawdown,
        flow_score: flow,
        score: score,
        valuation_label: valuation_label(blended_percentile, blended_pe, blended_pb),
        earnings_label: earnings_label(blended_earnings),
        risk_label: risk_label(config[:risk_base], blended_percentile),
        lumpsum_view: lumpsum_view(score, config[:risk_base]),
        commentary: segment_commentary(config[:label])
      }
    end

    def build_overall(segments, ranked_segments, source_data)
      average_score = average_numeric(segments.values.map { |segment| segment[:score] })
      average_valuation_percentile = average_numeric(segments.values.map { |segment| segment[:historical_pe_percentile] })
      average_earnings_growth = average_numeric(segments.values.map { |segment| segment[:earnings_growth] })
      average_momentum = average_numeric(segments.values.map { |segment| segment[:momentum_score] })
      top_segment = ranked_segments.first

      {
        headline: overall_headline(average_score),
        condition_label: overall_condition_label(average_score, average_valuation_percentile),
        score: average_score,
        valuation_percentile: average_valuation_percentile,
        valuation_band: valuation_band_label(average_valuation_percentile),
        earnings_growth: average_earnings_growth,
        momentum_score: average_momentum,
        top_segment: top_segment && top_segment[:label],
        market_bias: market_bias(top_segment),
        data_source_note: data_source_note(source_data)
      }
    end

    def build_checklist(input, overall, ranked_segments)
      top_segment = ranked_segments.first
      [
        checklist_item(
          "Investment horizon",
          numeric_label(input[:investment_horizon_years], suffix: " years"),
          !input[:investment_horizon_years].nil? && input[:investment_horizon_years].to_i >= 7,
          "Long enough for equity volatility"
        ),
        checklist_item(
          "Emergency fund",
          boolean_label(input[:emergency_fund_available]),
          input[:emergency_fund_available] == true,
          "Do not deploy lumpsum without a buffer"
        ),
        checklist_item(
          "Near-term cash need",
          boolean_label(input[:near_term_cash_requirement], positive: "Present", negative: "None"),
          input[:near_term_cash_requirement] == false,
          "Upcoming obligations reduce flexibility"
        ),
        checklist_item(
          "Current equity exposure",
          numeric_label(input[:current_equity_allocation_pct], suffix: "%"),
          within_target_band?(input[:current_equity_allocation_pct], input[:target_equity_allocation_pct]),
          "Keep allocation near the target band"
        ),
        checklist_item(
          "Market valuation",
          overall[:valuation_band],
          overall[:valuation_percentile].present? ? overall[:valuation_percentile].to_d <= 65 : nil,
          "Moderate valuation is easier to deploy into"
        ),
        checklist_item(
          "Segment concentration",
          numeric_label(input[:segment_concentration_pct], suffix: "%"),
          input[:segment_concentration_pct].present? ? input[:segment_concentration_pct].to_d <= 35 : nil,
          "Avoid one segment dominating the book"
        ),
        checklist_item(
          "Drawdown tolerance",
          numeric_label(input[:fall_tolerance_pct], suffix: "%"),
          input[:fall_tolerance_pct].present? ? input[:fall_tolerance_pct].to_d >= expected_drawdown_band(top_segment) : nil,
          "Lumpsum should survive a 25-35% fall"
        ),
        checklist_item(
          "Earnings trend",
          string_label(input[:major_earnings_trend]),
          input[:major_earnings_trend].present? ? %w[improving strong mixed].include?(input[:major_earnings_trend].to_s.downcase) : nil,
          "Earnings should not be deteriorating"
        ),
        checklist_item(
          "Policy tone",
          string_label(input[:rbi_policy_direction]),
          input[:rbi_policy_direction].present? ? policy_supportive?(input[:rbi_policy_direction]) : nil,
          "A neutral to easing stance helps risk appetite"
        ),
        checklist_item(
          "Upcoming obligations",
          boolean_label(input[:upcoming_obligations], positive: "Yes", negative: "No"),
          input[:upcoming_obligations] == false,
          "Fresh lumpsum is safer when liabilities are clear"
        )
      ]
    end

    def build_deployment(ranked_segments, checklist, overall)
      top_segment = ranked_segments.first
      readiness_score = checklist.count { |item| item[:status] == :pass }
      market_score = top_segment && top_segment[:score].present? ? top_segment[:score].to_d : 0

      if top_segment.nil?
        return {
          method: "Hold cash",
          rationale: "No ranking is available yet.",
          schedule: [{ label: "Keep dry powder", percent: 100 }]
        }
      end

      if market_score >= 75
        if readiness_score >= 7
          {
            method: "Immediate deployment",
            rationale: "Current valuation is reasonable, the horizon is long, and the readiness checks are in place.",
            schedule: [{ label: "Deploy now", percent: 100 }]
          }
        else
          {
            method: "Staggered lumpsum",
            rationale: "The market setup is strong, but missing readiness inputs still argue for spreading entry.",
            schedule: [
              { label: "Invest now", percent: 40 },
              { label: "After one month", percent: 20 },
              { label: "After two months", percent: 20 },
              { label: "Reserve for correction", percent: 20 }
            ]
          }
        end
      elsif market_score >= 60
        {
          method: "Staggered lumpsum",
          rationale: "The leading segment is investable, but staggered entry reduces timing risk.",
          schedule: [
            { label: "Invest now", percent: 40 },
            { label: "After one month", percent: 20 },
            { label: "After two months", percent: 20 },
            { label: "Reserve for correction", percent: 20 }
          ]
        }
      elsif market_score >= 45
        {
          method: "Partial entry",
          rationale: "The market is not cheap enough for full lumpsum deployment.",
          schedule: [
            { label: "Initial tranche", percent: 25 },
            { label: "After one month", percent: 25 },
            { label: "After two months", percent: 25 },
            { label: "Hold back", percent: 25 }
          ]
        }
      else
        {
          method: "Avoid fresh lumpsum",
          rationale: "The better segments still do not compensate for current valuation and risk.",
          schedule: [{ label: "Wait for a better setup", percent: 100 }]
        }
      end
    end

    def build_narrative(input, segments, overall, checklist, deployment)
      top_segment_label = overall[:top_segment].presence || "the large-cap segment"
      ranking = segments.values.sort_by do |segment|
        score = segment[:score].present? ? segment[:score].to_d : 0
        -score
      end
      fallback = {
        overall_summary: "Based on current valuation, returns and risk signals, #{top_segment_label} currently offers a relatively better risk reward profile than mid and small cap segments.",
        where_attractive_now: "#{ranking.map { |segment| segment[:label] }.join(', ')} are ranked from strongest to weakest risk reward.",
        deployment_note: "#{deployment[:method]} is the preferred method because not every readiness check passes yet."
      }

      return fallback if openai_api_key.blank? || @client.nil? || !@client.respond_to?(:responses)

      response = @client.responses.create(
        parameters: {
          model: MODEL,
          input: [
            { role: "system", content: narrative_prompt },
            { role: "user", content: narrative_payload(input, segments, overall, checklist, deployment).to_json }
          ],
          temperature: 0.2
        }
      )

      payload = JSON.parse(response.output_text)
      fallback.merge(
        overall_summary: payload["overall_summary"].to_s.strip.presence || fallback[:overall_summary],
        where_attractive_now: payload["where_attractive_now"].to_s.strip.presence || fallback[:where_attractive_now],
        deployment_note: payload["deployment_note"].to_s.strip.presence || fallback[:deployment_note]
      )
    rescue StandardError => e
      Rails.logger.warn("[MarketOpportunity::Analyzer] #{e.class}: #{e.message}")
      fallback
    end

    def narrative_prompt
      <<~PROMPT.squish
        You write concise market analysis copy for a portfolio dashboard.
        Use only the supplied JSON. Do not invent market data.
        Write plain text only in JSON with keys overall_summary, where_attractive_now, deployment_note.
        Keep each value short and direct.
      PROMPT
    end

    def narrative_payload(input, segments, overall, checklist, deployment)
      {
        overall: overall,
        source_as_of: input[:source_as_of],
        top_segments: segments.values.sort_by do |segment|
          score = segment[:score].present? ? segment[:score].to_d : 0
          -score
        end.map do |segment|
          {
            label: segment[:label],
            score: segment[:score],
            valuation_label: segment[:valuation_label],
            earnings_label: segment[:earnings_label],
            risk_label: segment[:risk_label],
            lumpsum_view: segment[:lumpsum_view]
          }
        end,
        checklist: checklist,
        deployment: deployment,
        inputs: input.slice(
          :market_breadth,
          :rbi_policy_direction,
          :major_earnings_trend,
          :investment_horizon_years,
          :emergency_fund_available,
          :near_term_cash_requirement,
          :current_equity_allocation_pct,
          :target_equity_allocation_pct,
          :segment_concentration_pct,
          :fall_tolerance_pct,
          :upcoming_obligations
        )
      }
    end

    def openai_client
      return nil if openai_api_key.blank?

      require "openai"
      OpenAI::Client.new(api_key: openai_api_key)
    rescue StandardError
      nil
    end

    def openai_api_key
      @openai_api_key ||= begin
        credentials = Rails.application.credentials
        credentials.dig(:openai, :api_key).presence ||
          credentials.gpt_api_key.presence ||
          ENV["OPENAI_API_KEY"].presence
      rescue StandardError
        ENV["OPENAI_API_KEY"].presence
      end
    end

    def valuation_score(pe, pb, percentile, dividend_yield)
      pe_score = score_lower_is_better(pe, [18, 26, 34, 45, 60])
      pb_score = score_lower_is_better(pb, [2.2, 3.3, 4.4, 5.5, 7.0])
      percentile_score = percentile.nil? ? nil : clamp_score(100 - percentile.to_d)
      dividend_score = dividend_yield.present? ? score_higher_is_better(dividend_yield, [1.0, 1.6, 2.2, 3.0, 4.0]) : nil

      weighted_score(
        [
          [pe_score, 0.40],
          [pb_score, 0.25],
          [percentile_score, 0.20],
          [dividend_score, 0.15]
        ]
      )
    end

    def earnings_score(growth, trend)
      return nil if growth.blank? && trend.blank?

      scores = []
      scores << score_higher_is_better(growth, [2, 6, 10, 15, 20]) if growth.present?

      trend_bonus = case trend.to_s.downcase
                    when "strong" then 12
                    when "improving" then 8
                    when "stable" then 4
                    when "mixed" then 0
                    when "weak" then -10
                    else nil
                    end
      scores << clamp_score(50 + trend_bonus) if trend_bonus

      weighted_score(scores.map { |score| [score, 1.0] })
    end

    def momentum_score(returns)
      usable = returns.compact
      return nil if usable.empty?

      weighted = weighted_average(usable, [0.5, 0.3, 0.2])
      return nil if weighted.nil?

      clamp_score(50 + (weighted.to_d * 2.2))
    end

    def breadth_score(breadth)
      return nil if breadth.blank?

      clamp_score(50 + ((breadth.to_d - 50) * 1.1))
    end

    def drawdown_score(risk_base, percentile, returns, valuation_score)
      return nil if risk_base.nil?

      recent_return = returns.first
      return nil if recent_return.nil? && percentile.nil? && valuation_score.nil?

      penalty = percentile.present? && percentile.to_d > 80 ? (percentile.to_d - 80) * 0.8 : 0
      momentum_bonus = if recent_return.nil?
                         0
                       elsif recent_return.positive?
                         [recent_return, 8].min
                       else
                         [recent_return.abs * 1.4, 10].min
                       end
      valuation_bonus = valuation_score.nil? ? 0 : valuation_score / 8.0
      clamp_score(100 - risk_base - penalty + momentum_bonus + valuation_bonus)
    end

    def flow_score(signal, risk_base)
      return nil if signal.blank?

      map = {
        "strong_inflow" => 90,
        "mild_inflow" => 74,
        "neutral" => 58,
        "mild_outflow" => 42,
        "heavy_outflow" => 24
      }
      base = map.fetch(signal.to_s.strip, 58)
      clamp_score(base - (risk_base.to_d / 20))
    end

    def opportunity_score(component_scores)
      weights = {
        valuation: 0.25,
        earnings: 0.20,
        momentum: 0.15,
        breadth: 0.10,
        drawdown: 0.15,
        flow: 0.15
      }

      usable = component_scores.select { |_, score| score.present? }
      return nil if usable.empty?

      total_weight = usable.sum { |key, _| weights.fetch(key, 0) }
      return nil if total_weight.zero?

      weighted = usable.sum { |key, score| score.to_d * weights.fetch(key, 0) }
      (weighted / total_weight).round(1)
    end

    def score_lower_is_better(value, bands)
      return nil if value.blank?

      numeric = value.to_d
      if numeric <= bands[0]
        95
      elsif numeric <= bands[1]
        85
      elsif numeric <= bands[2]
        70
      elsif numeric <= bands[3]
        52
      elsif numeric <= bands[4]
        35
      else
        20
      end
    end

    def score_higher_is_better(value, bands)
      return nil if value.blank?

      numeric = value.to_d
      if numeric <= bands[0]
        20
      elsif numeric <= bands[1]
        35
      elsif numeric <= bands[2]
        55
      elsif numeric <= bands[3]
        72
      elsif numeric <= bands[4]
        85
      else
        95
      end
    end

    def valuation_label(percentile, pe, pb)
      return "Unavailable" if percentile.blank? && pe.blank? && pb.blank?

      if percentile.present?
        case percentile.to_d
        when ..25 then "Cheap"
        when 25..50 then "Reasonable"
        when 50..75 then "Moderate"
        when 75..90 then "Expensive"
        else "Very expensive"
        end
      elsif pe.present? && pb.present?
        pe_label = if pe.to_d <= 18 then "Cheap"
                   elsif pe.to_d <= 26 then "Reasonable"
                   elsif pe.to_d <= 34 then "Moderate"
                   elsif pe.to_d <= 45 then "Expensive"
                   else "Very expensive"
                   end
        pb_label = if pb.to_d <= 2.2 then "Cheap"
                   elsif pb.to_d <= 3.3 then "Reasonable"
                   elsif pb.to_d <= 4.4 then "Moderate"
                   elsif pb.to_d <= 5.5 then "Expensive"
                   else "Very expensive"
                   end
        [pe_label, pb_label].group_by(&:itself).max_by { |_, values| values.size }.first
      else
        "Unavailable"
      end
    end

    def earnings_label(growth)
      return "Unavailable" if growth.blank?

      case growth.to_d
      when ..0 then "Contracting"
      when 0..5 then "Weak"
      when 5..10 then "Stable"
      when 10..15 then "Improving"
      else "Strong"
      end
    end

    def risk_label(risk_base, percentile)
      base = risk_base.to_i
      adjusted = base + (percentile.present? && percentile.to_d > 80 ? 5 : 0)

      case adjusted
      when ..35 then "Medium"
      when 36..55 then "High"
      when 56..70 then "High"
      else "Very high"
      end
    end

    def lumpsum_view(score, risk_base)
      return "Avoid fresh lumpsum" if risk_base.to_i >= 75 && score.to_d < 50
      return "Partial entry" if score.to_d < 60
      return "Staggered" if score.to_d < 75

      "Suitable"
    end

    def segment_commentary(label)
      if label == "Nifty 50"
        "Large caps are closer to historical valuation averages and carry a lower drawdown profile."
      elsif label == "Nifty Next 50"
        "The segment offers better growth than large caps, but valuation still needs discipline."
      elsif label.include?("Mid")
        "Mid caps can compound faster, but the valuation cushion is still thin."
      else
        "Small caps are vulnerable to valuation compression and liquidity shocks."
      end
    end

    def overall_headline(score)
      return "Overall Market Condition: Unavailable" if score.nil?

      case score
      when ..35 then "Overall Market Condition: Expensive"
      when 35..50 then "Overall Market Condition: Moderately Expensive"
      when 50..65 then "Overall Market Condition: Balanced"
      when 65..80 then "Overall Market Condition: Attractive"
      else "Overall Market Condition: Very Attractive"
      end
    end

    def overall_condition_label(score, valuation_percentile)
      return "Unavailable" if score.nil?

      case score
      when ..35 then "Defensive"
      when 35..50 then "Cautious"
      when 50..65 then "Balanced"
      when 65..80 then "Favourable"
      else "Strong"
      end
    end

    def market_bias(top_segment)
      return "Neutral" unless top_segment

      if top_segment[:key] == :nifty_50
        "Large caps currently carry the cleanest risk reward"
      elsif top_segment[:key] == :nifty_next_50
        "Next 50 offers a higher growth tilt with more risk"
      elsif top_segment[:key] == :mid_cap
        "Mid caps are selective only"
      else
        "Small caps are not ideal for fresh lumpsum"
      end
    end

    def checklist_item(label, value, passed, note)
      {
        label: label,
        value: value.presence || "Unavailable",
        status: passed == true ? :pass : :watch,
        note: note
      }
    end

    def boolean_label(value, positive: "Available", negative: "Missing")
      return "Unavailable" if value.nil?
      value ? positive : negative
    end

    def string_label(value)
      value.present? ? value.to_s.humanize : "Unavailable"
    end

    def numeric_label(value, suffix: nil)
      return "Unavailable" if value.nil?

      formatted = value.to_d.round(1).to_s("F")
      "#{formatted}#{suffix}"
    end

    def within_target_band?(current, target)
      return nil if current.nil? || target.nil?

      current.to_d <= target.to_d + 5 && current.to_d >= target.to_d - 10
    end

    def valuation_band_label(percentile)
      return "Unavailable" if percentile.blank?

      case percentile.to_d
      when ..35 then "Moderate"
      when 35..60 then "Moderate"
      when 60..75 then "Stretched"
      else "Very expensive"
      end
    end

    def policy_supportive?(policy_direction)
      %w[easing neutral supportive].include?(policy_direction.to_s.downcase)
    end

    def expected_drawdown_band(top_segment)
      return 25 if top_segment.blank?
      return 30 if top_segment[:key] == :nifty_50
      return 35 if top_segment[:key] == :nifty_next_50
      return 40 if top_segment[:key] == :large_cap
      return 45 if top_segment[:key] == :mid_cap

      50
    end

    def weighted_average(values, weights)
      filtered = values.compact.map(&:to_d)
      return nil if filtered.empty?
      return filtered.first.round(2) if filtered.size == 1

      usable_weights = weights.first(filtered.size)
      total_weight = usable_weights.sum.to_d
      return nil if total_weight.zero?

      (filtered.zip(usable_weights).sum { |value, weight| value * weight.to_d } / total_weight).round(2)
    end

    def average_numeric(values)
      filtered = values.compact.map(&:to_d)
      return nil if filtered.empty?

      (filtered.sum / filtered.size.to_d).round(1)
    end

    def weighted_score(weighted_pairs)
      usable = weighted_pairs.select { |score, _| score.present? }
      return nil if usable.empty?

      total_weight = usable.sum { |_, weight| weight.to_d }
      return nil if total_weight.zero?

      weighted_total = usable.sum { |score, weight| score.to_d * weight.to_d }
      (weighted_total / total_weight).round(1)
    end

    def clamp_score(value)
      [[value.to_d.round(1), 0].max, 100].min
    end

    def data_source_note(source_data)
      return "Live NSE factsheets are unavailable right now." if source_data[:source_as_of].blank?

      "Live NSE factsheets as of #{source_data[:source_as_of]}. Fields left blank are unavailable from the source."
    end
  end
end
