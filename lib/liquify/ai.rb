require 'net/http'
require 'uri'
require 'json'

module Liquify
  module AI
    SYSTEM_PROMPT = <<~PROMPT
      You are a Shopify Liquid performance expert.
      You will be given a single Liquid template snippet that contains an N+1 database query pattern.

      Your task:
      - Refactor the code to eliminate the N+1 query
      - Batch data fetching OUTSIDE the loop using assign or map where possible
      - Preserve the original HTML structure and output

      Rules:
      - Return ONLY the refactored Liquid code, nothing else
      - Do NOT repeat the original code
      - Do NOT include explanations, headers, labels, or commentary
      - Do NOT use markdown, code fences, or any special characters
      - Do NOT include symbols like ⚠, ↳, ✦, or similar
      - If the snippet is a single line with no loop context, just return the optimized version of that line
      - If the full context is needed, make reasonable assumptions
    PROMPT

    def self.detect_provider
      return :anthropic if ENV['ANTHROPIC_API_KEY']
      return :openai    if ENV['OPENAI_API_KEY']
      return :gemini    if ENV['GEMINI_API_KEY']
      nil
    end

    def self.refactor(snippet, full_template)
      prompt = build_prompt(snippet, full_template)
      raw = case detect_provider
            when :anthropic then call_anthropic(prompt)
            when :openai    then call_openai(prompt)
            when :gemini    then call_gemini(prompt)
            end
      sanitize(raw)
    end

    def self.build_prompt(snippet, full_template)
      <<~PROMPT
        Here is the full Liquid template for context:

        #{full_template}

        The following specific line was flagged as an N+1 query:

        #{snippet}

        Refactor the relevant section of the template to fix this N+1 issue.
      PROMPT
    end

    def self.fix_template(full_template, issues)
      flagged = issues.map.with_index(1) do |issue, i|
        "Issue ##{i} (Line #{issue['line_number']}): #{issue['code_snippet'].strip}"
      end.join("\n")

      prompt = <<~PROMPT
        Here is a Shopify Liquid template with N+1 database query issues:

        #{full_template}

        The following lines were flagged as N+1 queries:

        #{flagged}

        Return the COMPLETE fixed template with ALL issues resolved.
        Rules:
        - Return ONLY the full fixed Liquid template, nothing else
        - Do NOT include explanations, markdown, or code fences
        - Preserve all HTML structure, whitespace style, and comments
        - Batch data fetching outside loops using assign or map
      PROMPT

      raw = case detect_provider
            when :anthropic then call_anthropic(prompt)
            when :openai    then call_openai(prompt)
            when :gemini    then call_gemini(prompt)
            end
      sanitize(raw)
    end

    def self.sanitize(response)
      return nil if response.nil?
      # Strip any lines that contain our own formatting markers
      # (happens when the AI mimics the tool's output format)
      cleaned = response.lines.reject { |l| l.match?(/[⚠↳✦]/) }.join
      cleaned.strip
    end

    private

    def self.call_anthropic(prompt)
      require 'anthropic'
      client   = Anthropic::Client.new(access_token: ENV['ANTHROPIC_API_KEY'])
      response = client.messages(
        parameters: {
          model:      'claude-opus-4-6',
          max_tokens: 1024,
          system:     SYSTEM_PROMPT,
          messages:   [{ role: 'user', content: prompt }]
        }
      )
      response.dig('content', 0, 'text')&.strip
    rescue => e
      handle_error(:anthropic, e)
    end

    def self.call_openai(prompt)
      require 'openai'
      client   = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
      response = client.chat(
        parameters: {
          model:    'gpt-4o',
          messages: [
            { role: 'system', content: SYSTEM_PROMPT },
            { role: 'user',   content: prompt }
          ]
        }
      )
      response.dig('choices', 0, 'message', 'content')&.strip
    rescue => e
      handle_error(:openai, e)
    end

    def self.call_gemini(prompt)
      api_key  = ENV['GEMINI_API_KEY']
      endpoint = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=#{api_key}")
      body     = {
        system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ role: 'user', parts: [{ text: prompt }] }]
      }.to_json

      http         = Net::HTTP.new(endpoint.host, endpoint.port)
      http.use_ssl = true
      req          = Net::HTTP::Post.new(endpoint)
      req['Content-Type'] = 'application/json'
      req.body     = body

      parsed = JSON.parse(http.request(req).body)
      parsed.dig('candidates', 0, 'content', 'parts', 0, 'text')&.strip
    rescue => e
      handle_error(:gemini, e)
    end

    def self.handle_error(provider, error)
      msg = case error.class.to_s
            when /Unauthorized/, /401/  then "Invalid API key for #{provider}. Check your #{provider.upcase}_API_KEY."
            when /ResourceNotFound/,
                 /NotFound/, /404/      then "Model not available on your #{provider} plan. Try a different model or plan."
            when /TooManyRequests/, /429/ then "Rate limit hit for #{provider}. Wait a moment and try again."
            when /Timeout/, /Connection/ then "Could not reach #{provider} API. Check your internet connection."
            else                          "#{provider.capitalize} API error: #{error.message}"
            end
      $stderr.puts "  \e[33m⚠  #{msg}\e[0m"
      nil
    end
  end
end
