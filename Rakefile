# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Native extension tasks are only wired up when rake-compiler is available, so
# the pure-Ruby workflow (and `rake spec`) never depends on a compiler or on
# MuPDF being installed.
begin
  require "rake/extensiontask"

  Rake::ExtensionTask.new("rudf_native") do |ext|
    ext.ext_dir = "ext/rudf_native"
    ext.lib_dir = "lib/rudf"
    # Cross-compilation targets for precompiled platform gems (built in CI via
    # rake-compiler-dock).
    ext.cross_compile = true
    ext.cross_platform = %w[
      x86_64-linux aarch64-linux
      x86_64-darwin arm64-darwin
      x64-mingw-ucrt
    ]
  end
rescue LoadError
  # rake-compiler not installed: native tasks are unavailable, pure-Ruby only.
end

task default: :spec
