require 'open3'
require 'tempfile'
require 'json'

module Liquify
  module Analyzer
    # The compiled C++ binary sits inside cpp_engine/ at the repo root
    # On Windows g++ produces .exe, on Unix no extension
    _base   = File.expand_path('../../../cpp_engine/liquid_analyzer', __FILE__)
    BINARY  = File.exist?(_base + '.exe') ? _base + '.exe' : _base

    def self.run(file_path)
      ensure_binary!

      stdout, stderr, status = Open3.capture3(BINARY, file_path)

      unless status.success?
        raise "Analyzer binary failed: #{stderr.strip}"
      end

      JSON.parse(stdout)
    end

    def self.run_code(code)
      tmp = Tempfile.new(['liquify_', '.liquid'])
      begin
        tmp.write(code)
        tmp.flush
        run(tmp.path)
      ensure
        tmp.close
        tmp.unlink
      end
    end

    private

    def self.ensure_binary!
      return if File.exist?(BINARY)

      src  = File.expand_path('../../../cpp_engine/analyzer.cpp', __FILE__)
      raise "analyzer.cpp not found at #{src}" unless File.exist?(src)

      base = File.expand_path('../../../cpp_engine/liquid_analyzer', __FILE__)
      puts "  Compiling C++ engine..."
      system("g++ -std=c++17 -O2 -o \"#{base}\" \"#{src}\"")

      compiled = File.exist?(base) || File.exist?(base + '.exe')
      raise "Compilation failed. Is g++ installed?" unless compiled
    end
  end
end
