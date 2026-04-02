require 'net/http'
require 'uri'
require 'json'

module Liquify
  module AI
    SYSTEM_PROMPT = <<~PROMPT
      You are a Shopify Liquid performance expert.
      You will be given a Liquid template snippet that contains an N+1 database query pattern.

      Your task:
      - Refactor the code to eliminate the N+1 query
      - Batch data fetching OUTSIDE the loop using assign or map where possible
      - Preserve the original HTML structure and output

      Rules:
      - Return ONLY the refactored Liquid code
      - No explanations, no markdown, no code fences
      - If the full context is needed, make reasonable assumptions
    PROMPT

    def self.detect_provider
      return :anthropic if ENV['ANTHROPIC_API_KEY']
      return :openai    if ENV['OPENAI_API_KEY']
      return :gemini    if ENV['GEMINI_API_KEY']
      nil
    end

    def self.refactor(snippet)
      case detect_provider
      when :anthropic then call_anthropic(snippet)
      when :openai    then call_openai(snippet)
      when :gemini    then call_gemini(snippet)
      end
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
          model:    'gpt-4.5-preview',
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
