require 'open3'
require 'tempfile'
require 'json'
require 'rbconfig'

module Liquify
  module Analyzer
    ROOT = File.expand_path('../../../', __FILE__)

    # Resolve the correct pre-compiled binary for the current platform.
    # Falls back to a locally compiled binary if the distributed one isn't found.
    def self.binary_path
      platform_name = case RbConfig::CONFIG['host_os']
                      when /mswin|mingw|cygwin/ then 'liquid_analyzer-windows.exe'
                      when /darwin/             then
                        RbConfig::CONFIG['host_cpu'] =~ /arm|aarch64/ ?
                          'liquid_analyzer-macos-arm64' : 'liquid_analyzer-macos'
                      else                           'liquid_analyzer-linux'
                      end

      distributed = File.join(ROOT, 'cpp_engine', 'bin', platform_name)
      return distributed if File.exist?(distributed)

      # Fall back to locally compiled binary
      local = File.join(ROOT, 'cpp_engine', 'liquid_analyzer')
      return local + '.exe' if File.exist?(local + '.exe')
      local
    end

    def self.run(file_path)
      binary = binary_path
      ensure_binary!(binary)

      stdout, stderr, status = Open3.capture3(binary, file_path)
      raise "Analyzer binary failed: #{stderr.strip}" unless status.success?

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

    def self.ensure_binary!(binary)
      return if File.exist?(binary)

      src  = File.join(ROOT, 'cpp_engine', 'analyzer.cpp')
      raise "analyzer.cpp not found at #{src}" unless File.exist?(src)

      out = File.join(ROOT, 'cpp_engine', 'liquid_analyzer')
      puts "  Pre-compiled binary not found. Compiling from source..."
      puts "  (tip: run the GitHub Actions workflow to generate pre-compiled binaries)"
      system("g++ -std=c++17 -O2 -o \"#{out}\" \"#{src}\"")

      compiled = File.exist?(out) || File.exist?(out + '.exe')
      raise "Compilation failed. Is g++ installed?" unless compiled
    end
  end
end
