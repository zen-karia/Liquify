module Liquify
  module Formatter
    # ANSI color codes
    RESET  = "\e[0m"
    BOLD   = "\e[1m"
    RED    = "\e[31m"
    GREEN  = "\e[32m"
    YELLOW = "\e[33m"
    CYAN   = "\e[36m"
    GRAY   = "\e[90m"

    WIDTH  = 58

    def self.c(text, *codes)
      "#{codes.join}#{text}#{RESET}"
    end

    def self.divider(char = '─')
      c(char * WIDTH, GRAY)
    end

    def self.render(file_path, issues, provider)
      lines = []

      # Header
      lines << c("╔#{'═' * WIDTH}╗", CYAN)
      lines << c("║#{' LIQUIFY — Shopify Liquid N+1 Analyzer '.center(WIDTH)}║", CYAN + BOLD)
      lines << c("╚#{'═' * WIDTH}╝", CYAN)
      lines << ''

      lines << "  Scanning : #{c(file_path, BOLD)}"

      if provider
        lines << "  Provider : #{c(provider.to_s.capitalize, BOLD + CYAN)}"
      else
        lines << "  Provider : #{c('None', YELLOW)} #{c('(set ANTHROPIC_API_KEY, OPENAI_API_KEY, or GEMINI_API_KEY)', GRAY)}"
      end

      lines << ''

      if issues.empty?
        lines << divider
        lines << "  #{c('✓', GREEN + BOLD)}  #{c('No N+1 issues found. Your template looks clean!', GREEN + BOLD)}"
        lines << divider
      else
        issues.each_with_index do |issue, i|
          lines << divider
          lines << "  #{c("ISSUE ##{i + 1}  —  Line #{issue['line_number']}", YELLOW + BOLD)}"
          lines << divider
          lines << ''
          lines << "  #{c('⚠  ' + issue['issue'], RED + BOLD)}"
          lines << "  #{c('↳  ' + issue['code_snippet'].strip, RED)}"
          lines << ''

          if issue['optimized_code'] && !issue['optimized_code'].empty?
            lines << "  #{c('✦  Optimized Code:', GREEN + BOLD)}"
            issue['optimized_code'].each_line do |ln|
              lines << "     #{c(ln.chomp, GREEN)}"
            end
          elsif provider.nil?
            lines << "  #{c('✦  Set an API key to get an AI-generated fix.', GRAY)}"
          end

          lines << ''
        end

        lines << divider
        lines << "  #{c("#{issues.size} issue(s) found.", YELLOW + BOLD)}"
        lines << c('═' * WIDTH, CYAN)
      end

      lines.join("\n")
    end
  end
end
