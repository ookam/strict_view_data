# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'strict_view_data'
  spec.version = '0.1.0'
  spec.authors = [ 'ookam' ]
  spec.summary = 'RailsのView入力を明示的な登録と読み取りに限定します。'
  spec.description = 'view_dataによる入力の登録、厳密なドットアクセス、テンプレートの暗黙参照の検査を提供します。'
  spec.homepage = 'https://github.com/ookam/strict_view_data'
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues"
  }
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir.glob([ 'lib/**/*.rb', 'README.md' ], base: __dir__)
  spec.require_paths = [ 'lib' ]
  spec.add_dependency 'actionpack', '~> 8.1.0'
  spec.add_dependency 'actionview', '~> 8.1.0'
  spec.add_dependency 'prism', '~> 1.9'
end
