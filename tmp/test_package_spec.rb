# frozen_string_literal: true

require 'tmpdir'
require_relative '../lib/strict_view_data'

RSpec.describe '配布パッケージの範囲' do
  it '別のディレクトリから読んでもGem自身のファイルだけを配布する' do
    path = File.expand_path('../strict_view_data.gemspec', __dir__)
    specification = Dir.mktmpdir('test_package_', __dir__) do |directory|
      Dir.chdir(directory) { Gem::Specification.load(path) }
    end
    expect(specification.files).to contain_exactly('README.md', 'lib/strict_view_data.rb',
      'lib/strict_view_data/rails.rb', 'lib/strict_view_data/template_check.rb')
    expect(specification.version.to_s).to eq(StrictViewData::VERSION)
  end

  it '利用者がソースと不具合報告先を確認できる' do
    specification = Gem::Specification.load(File.expand_path('../strict_view_data.gemspec', __dir__))
    expect(specification.homepage).to eq('https://github.com/ookam/strict_view_data')
    expect(specification.metadata).to include(
      'source_code_uri' => 'https://github.com/ookam/strict_view_data',
      'bug_tracker_uri' => 'https://github.com/ookam/strict_view_data/issues'
    )
  end
end
