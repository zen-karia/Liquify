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

    def self.call_anthropic(snippet)
      require 'anthropic'
      client   = Anthropic::Client.new(access_token: ENV['ANTHROPIC_API_KEY'])
      response = client.messages(
        parameters: {
          model:      'claude-opus-4-6',
          max_tokens: 1024,
          system:     SYSTEM_PROMPT,
          messages:   [{ role: 'user', content: snippet }]
        }
      )
      response.dig('content', 0, 'text')&.strip
    end

    def self.call_openai(snippet)
      require 'openai'
      client   = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
      response = client.chat(
        parameters: {
          model:    'gpt-4o',
          messages: [
            { role: 'system', content: SYSTEM_PROMPT },
            { role: 'user',   content: snippet }
          ]
        }
      )
      response.dig('choices', 0, 'message', 'content')&.strip
    end

    def self.call_gemini(snippet)
      api_key  = ENV['GEMINI_API_KEY']
      endpoint = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key=#{api_key}")
      body     = {
        system_instruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ role: 'user', parts: [{ text: snippet }] }]
      }.to_json

      http         = Net::HTTP.new(endpoint.host, endpoint.port)
      http.use_ssl = true
      req          = Net::HTTP::Post.new(endpoint)
      req['Content-Type'] = 'application/json'
      req.body     = body

      parsed = JSON.parse(http.request(req).body)
      parsed.dig('candidates', 0, 'content', 'parts', 0, 'text')&.strip
    end
  end
end
