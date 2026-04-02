require_relative 'lib/liquify/version'

Gem::Specification.new do |spec|
  spec.name          = 'liquify'
  spec.version       = Liquify::VERSION
  spec.authors       = ['Zenil Karia']
  spec.summary       = 'Shopify Liquid N+1 query analyzer with AI-powered refactoring'
  spec.description   = 'A CLI tool that detects N+1 database query patterns in Shopify Liquid templates and suggests AI-powered fixes using Claude, GPT-4o, or Gemini.'
  spec.license       = 'MIT'

  spec.executables   = ['liquify']
  spec.files         = Dir['lib/**/*', 'bin/*', 'cpp_engine/analyzer.cpp']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.0'

  # AI providers — all optional, user supplies whichever key they have
  spec.add_dependency 'anthropic',   '~> 0.4'
  spec.add_dependency 'ruby-openai', '~> 7.0'
  # Gemini uses net/http directly — no gem needed
end
