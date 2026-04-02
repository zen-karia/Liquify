require 'diff/lcs'
require 'diff/lcs/hunk'

module Liquify
  module Differ
    RESET  = "\e[0m"
    RED    = "\e[31m"
    GREEN  = "\e[32m"
    CYAN   = "\e[36m"
    GRAY   = "\e[90m"
    BOLD   = "\e[1m"

    def self.render(original, fixed, file_path)
      orig_lines  = original.lines
      fixed_lines = fixed.lines
      diffs       = Diff::LCS.diff(orig_lines, fixed_lines)

      return "  #{GRAY}(no changes detected)#{RESET}" if diffs.empty?

      output = []
      output << "#{CYAN}#{BOLD}--- #{file_path} (original)#{RESET}"
      output << "#{CYAN}#{BOLD}+++ #{file_path} (fixed)#{RESET}"
      output << ''

      # Build a map of changed line numbers for context display
      removed = {}  # orig line index => content
      added   = {}  # fixed line index => content

      diffs.each do |hunk|
        hunk.each do |change|
          if change.action == '-'
            removed[change.position] = change.element
          elsif change.action == '+'
            added[change.position] = change.element
          end
        end
      end

      # Render with context (3 lines around each change)
      context    = 3
      shown      = {}
      max_line   = [orig_lines.size, fixed_lines.size].max

      # Build a unified view by walking original lines
      orig_idx  = 0
      fixed_idx = 0

      while orig_idx < orig_lines.size || fixed_idx < fixed_lines.size
        if removed.key?(orig_idx)
          output << "#{RED}-  #{orig_lines[orig_idx].chomp}#{RESET}"
          orig_idx += 1
        elsif added.key?(fixed_idx)
          output << "#{GREEN}+  #{fixed_lines[fixed_idx].chomp}#{RESET}"
          fixed_idx += 1
        else
          line = orig_lines[orig_idx]&.chomp || ''
          output << "#{GRAY}   #{line}#{RESET}"
          orig_idx  += 1
          fixed_idx += 1
        end
      end

      output.join("\n")
    end
  end
end
