require_relative 'analyzer'
require_relative 'ai'
require_relative 'formatter'
require 'json'

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

      fix_mode    = argv.include?('--fix')
      json_mode   = argv.include?('--format=json') || argv.include?('--json')
      raw_paths   = argv.reject { |a| a.start_with?('-') }

      if raw_paths.empty?
        warn "Error: no file(s) or directory specified."
        print_usage
        exit 1
      end

      # Expand directories recursively into .liquid files
      files = expand_paths(raw_paths)

      if files.empty?
        warn "Error: no .liquid files found."
        exit 1
      end

      all_results = []

      files.each do |file_path|
        unless File.exist?(file_path)
          warn "Error: file not found — #{file_path}"
          next
        end

        provider = Liquify::AI.detect_provider

        begin
          issues = Liquify::Analyzer.run(file_path)
        rescue => e
          warn "Error running analyzer on #{file_path}: #{e.message}"
          next
        end

        if issues.any? && provider
          full_template = File.read(file_path)

          if fix_mode
            fixed_template = Liquify::AI.fix_template(full_template, issues)

            if fixed_template && !fixed_template.empty?
              backup_path = file_path + '.bak'
              File.write(backup_path, full_template)
              File.write(file_path, fixed_template)
              issues.each { |i| i['auto_fixed'] = true }
              puts Liquify::Formatter.render(file_path, issues, provider, backup_path: backup_path) unless json_mode
            else
              warn "  Error: AI did not return a valid fixed template for #{file_path}."
              puts Liquify::Formatter.render(file_path, issues, provider) unless json_mode
            end
          else
            issues.each do |issue|
              issue['optimized_code'] = Liquify::AI.refactor(issue['code_snippet'], full_template)
            end
            puts Liquify::Formatter.render(file_path, issues, provider) unless json_mode
          end
        else
          puts Liquify::Formatter.render(file_path, issues, provider) unless json_mode
        end

        all_results << { file: file_path, issues: issues }
        puts '' if files.size > 1 && !json_mode
      end

      # JSON output mode — print all results as one JSON array
      if json_mode
        puts JSON.pretty_generate(all_results)
      end
    end

    def self.expand_paths(paths)
      paths.flat_map do |path|
        if File.directory?(path)
          Dir.glob(File.join(path, '**', '*.liquid')).sort
        else
          [path]
        end
      end
    end

    def self.print_usage
      puts <<~USAGE
        Usage: liquify <file.liquid|directory> [more files...] [options]

        Options:
          --fix              Auto-apply AI fixes directly to the file (saves .bak backup)
          --format=json      Output results as JSON (useful for CI/CD pipelines)
          -h, --help         Show this help
          -v, --version      Show version

        API Keys (set whichever you have):
          ANTHROPIC_API_KEY   Use Claude for AI refactoring
          OPENAI_API_KEY      Use GPT-4o for AI refactoring
          GEMINI_API_KEY      Use Gemini for AI refactoring

        Examples:
          liquify templates/product.liquid
          liquify templates/
          liquify templates/ --format=json
          ANTHROPIC_API_KEY=sk-... liquify templates/ --fix
      USAGE
    end
  end
end
