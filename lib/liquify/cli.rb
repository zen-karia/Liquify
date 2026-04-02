require_relative 'analyzer'
require_relative 'ai'
require_relative 'formatter'

module Liquify
  module CLI
    def self.run(argv)
      if argv.empty? || argv.include?('--help') || argv.include?('-h')
        print_usage
        exit 0
      end

      if argv.include?('--version') || argv.include?('-v')
        puts "liquify #{Liquify::VERSION}"
        exit 0
      end

      files = argv.reject { |a| a.start_with?('-') }

      if files.empty?
        puts "Error: no file(s) specified."
        print_usage
        exit 1
      end

      files.each do |file_path|
        unless File.exist?(file_path)
          puts "Error: file not found — #{file_path}"
          next
        end

        provider = Liquify::AI.detect_provider

        begin
          issues = Liquify::Analyzer.run(file_path)
        rescue => e
          puts "Error running analyzer: #{e.message}"
          exit 1
        end

        # Enrich each issue with AI-generated fix if a provider is available
        if issues.any? && provider
          issues.each do |issue|
            issue['optimized_code'] = Liquify::AI.refactor(issue['code_snippet'])
          end
        end

        puts Liquify::Formatter.render(file_path, issues, provider)
        puts '' if files.size > 1
      end
    end

    def self.print_usage
      puts <<~USAGE
        Usage: liquify <file.liquid> [file2.liquid ...]

        Options:
          -h, --help       Show this help
          -v, --version    Show version

        API Keys (set whichever you have):
          ANTHROPIC_API_KEY   Use Claude for AI refactoring
          OPENAI_API_KEY      Use GPT-4o for AI refactoring
          GEMINI_API_KEY      Use Gemini for AI refactoring

        Example:
          liquify templates/product.liquid
          ANTHROPIC_API_KEY=sk-... liquify templates/product.liquid
      USAGE
    end
  end
end
