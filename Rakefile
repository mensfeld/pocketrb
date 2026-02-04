# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]

namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = "spec/unit/**/*_spec.rb"
  end

  RSpec::Core::RakeTask.new(:integration) do |t|
    t.pattern = "spec/integration/**/*_spec.rb"
  end
end

desc "Run all tests with coverage"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task["spec"].invoke
end

desc "Generate YARD documentation"
task :docs do
  sh "yard doc --output-dir doc lib/"
end

desc "Run YARD documentation linter"
task :yard_lint do
  require "yard"
  YARD::CLI::Yardoc.run("--no-save", "--no-output")

  total = YARD::Registry.all(:method, :class, :module).count
  documented = YARD::Registry.all(:method, :class, :module)
                             .reject { |o| o.docstring.blank? }
                             .count

  coverage = (documented.to_f / total * 100).round(2)
  puts "Documentation: #{documented}/#{total} (#{coverage}%)"

  exit 1 if documented < total
end

desc "Show YARD documentation statistics"
task :yard_stats do
  sh "yard stats --list-undoc"
end
