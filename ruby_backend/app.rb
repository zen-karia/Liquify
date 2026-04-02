require 'sinatra'
require 'json'
require 'open3'
require 'tempfile'
require 'net/http'
require 'uri'

# AI provider gems
require 'anthropic'
require 'openai'

set :port, 4567
set :bind, '0.0.0.0'

CPP_BINARY = File.expand_path('../cpp_engine/liquid_analyzer', __dir__)

AI_SYSTEM_PROMPT = <<~PROMPT
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

before do
  content_type :json
end

# --- AI provider selector ---
# Priority: Anthropic → OpenAI → Gemini
def detect_provider
  return :anthropic if ENV['ANTHROPIC_API_KEY']
  return :openai    if ENV['OPENAI_API_KEY']
  return :gemini    if ENV['GEMINI_API_KEY']
  nil
end

def call_ai(snippet)
  provider = detect_provider
  return nil if provider.nil?

  case provider

  when :anthropic
    client   = Anthropic::Client.new(access_token: ENV['ANTHROPIC_API_KEY'])
    response = client.messages(
      parameters: {
        model:      'claude-opus-4-6',
        max_tokens: 1024,
        system:     AI_SYSTEM_PROMPT,
        messages:   [{ role: 'user', content: snippet }]
      }
    )
    response.dig('content', 0, 'text')&.strip

  when :openai
    client   = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    response = client.chat(
      parameters: {
        model:    'gpt-4o',
        messages: [
          { role: 'system', content: AI_SYSTEM_PROMPT },
          { role: 'user',   content: snippet }
        ]
      }
    )
    response.dig('choices', 0, 'message', 'content')&.strip

  when :gemini
    # Direct REST call — avoids libcurl dependency
    api_key  = ENV['GEMINI_API_KEY']
    endpoint = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{api_key}")
    body     = {
      system_instruction: { parts: [{ text: AI_SYSTEM_PROMPT }] },
      contents: [{ role: 'user', parts: [{ text: snippet }] }]
    }.to_json

    http          = Net::HTTP.new(endpoint.host, endpoint.port)
    http.use_ssl  = true
    request       = Net::HTTP::Post.new(endpoint)
    request['Content-Type'] = 'application/json'
    request.body  = body

    response = http.request(request)
    parsed   = JSON.parse(response.body)
    parsed.dig('candidates', 0, 'content', 'parts', 0, 'text')&.strip
  end
end

# --- POST /analyze ---
post '/analyze' do
  body_str = request.body.read
  begin
    payload = JSON.parse(body_str)
  rescue JSON::ParserError
    halt 400, { error: 'Invalid JSON body' }.to_json
  end

  code = payload['code']
  halt 400, { error: 'Missing "code" field' }.to_json if code.nil? || code.strip.empty?

  tmp = Tempfile.new(['liquid_', '.liquid'])
  begin
    tmp.write(code)
    tmp.flush

    stdout, stderr, status = Open3.capture3(CPP_BINARY, tmp.path)

    unless status.success?
      halt 500, { error: 'Analyzer binary failed', detail: stderr.strip }.to_json
    end

    results = JSON.parse(stdout)

    response_body =
      if results.any?
        provider = detect_provider

        if provider.nil?
          results.each { |r| r['optimized_code'] = nil }
          {
            provider_used: nil,
            notice:        'Set ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY to enable AI refactoring.',
            issues:        results
          }
        else
          results.each do |issue|
            issue['optimized_code'] = call_ai(issue['code_snippet'])
            issue['provider_used']  = provider.to_s
          end
          results
        end
      else
        results
      end

    response_body.to_json

  rescue JSON::ParserError
    halt 500, { error: 'Analyzer returned invalid JSON', raw: stdout }.to_json
  ensure
    tmp.close
    tmp.unlink
  end
end
