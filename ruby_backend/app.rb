require 'sinatra'
require 'json'
require 'open3'
require 'tempfile'

set :port, 4567
set :bind, '0.0.0.0'

# Path to the compiled C++ binary (relative to this file's location)
CPP_BINARY = File.expand_path('../cpp_engine/liquid_analyzer', __dir__)

before do
  content_type :json
end

post '/analyze' do
  # --- Parse incoming JSON body ---
  body_str = request.body.read
  begin
    payload = JSON.parse(body_str)
  rescue JSON::ParserError
    halt 400, { error: 'Invalid JSON body' }.to_json
  end

  code = payload['code']
  halt 400, { error: 'Missing "code" field' }.to_json if code.nil? || code.strip.empty?

  # --- Write code to a temp file ---
  tmp = Tempfile.new(['liquid_', '.liquid'])
  begin
    tmp.write(code)
    tmp.flush

    # --- Run the C++ binary ---
    stdout, stderr, status = Open3.capture3(CPP_BINARY, tmp.path)

    unless status.success?
      halt 500, { error: 'Analyzer binary failed', detail: stderr.strip }.to_json
    end

    # --- Parse and return the JSON from C++ stdout ---
    results = JSON.parse(stdout)
    results.to_json

  rescue JSON::ParserError
    halt 500, { error: 'Analyzer returned invalid JSON', raw: stdout }.to_json
  ensure
    tmp.close
    tmp.unlink  # delete temp file
  end
end
