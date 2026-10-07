# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = 'tmp/test_*_spec.rb'
  task.rspec_opts = '--options /dev/null --format progress'
end

task default: :spec
