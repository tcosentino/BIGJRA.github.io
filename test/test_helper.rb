require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'

# Paths can be overridden with env vars; defaults assume the layout
# <root>/upstream (this repo), <root>/game-scripts, <root>/out/baseline.
module TestPaths
  REPO_DIR = File.expand_path('..', __dir__)
  GAME_SCRIPTS = ENV['WT_GAME_SCRIPTS'] || File.expand_path('../game-scripts', REPO_DIR)
  BASELINE_DIR = ENV['WT_BASELINE_DIR'] || File.expand_path('../out/baseline', REPO_DIR)
end

# Runs the generator once per test process (HTML markdown + JSON export)
# and returns the output directory.
module GeneratedOutput
  def self.dir
    @dir ||= begin
      dir = Dir.mktmpdir('wt-test')
      Minitest.after_run { FileUtils.rm_rf(dir) }
      cmd = ['ruby', 'wt_generator.rb', 'reborn', TestPaths::GAME_SCRIPTS, File.join(dir, 'reborn.md')]
      out, status = Open3.capture2e(*cmd, chdir: TestPaths::REPO_DIR)
      raise "Generator failed:\n#{out}" unless status.success?
      dir
    end
  end

  def self.json(path)
    @json ||= {}
    @json[path] ||= JSON.parse(File.read(File.join(dir, 'json', path)))
  end
end
