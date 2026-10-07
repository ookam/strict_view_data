# frozen_string_literal: true

require 'tmpdir'
require 'timeout'
require 'action_controller'
require 'action_view'
require_relative '../lib/strict_view_data'

# @note 同じコンパイル済みテンプレートを通常のControllerから描画する。
class TestLifecycleOrdinaryController < ActionController::Base
end

# @note 通常のControllerと共有したテンプレートにも明示的入力の検査を適用する。
class TestLifecycleStrictController < ActionController::Base
  include StrictViewData::Controller
end

RSpec.describe 'テンプレートのコンパイルと検査の整合性', type: :controller do
  around do |example|
    Dir.mktmpdir('test_template_lifecycle_', __dir__) do |directory|
      @template_path = File.join(directory, 'show.html.erb')
      @view_class = ActionView::Base.with_empty_template_cache
      example.run
    end
  end

  # @note 同じコンパイル先を持ち、リクエストごとに異なるControllerを使うViewを作る。
  # @param controller_class [Class] Gemを適用するかを決めるControllerの型。
  # @return [ActionView::Base] 空の入力から開始する独立した描画コンテキスト。
  def lifecycle_view(controller_class: TestLifecycleStrictController)
    return @view_class.new(ActionView::LookupContext.new([]), {}, controller_class.new)
  end

  # @note ファイルが変更されても同じオブジェクトを返すResolverのテンプレートを再現する。
  # @param source [String] 最初のコンパイルで読み込むERBの本文。
  # @return [ActionView::Template] ファイルから読み込む未コンパイルのテンプレート。
  def lifecycle_template(source)
    File.write(@template_path, source)
    return ActionView::Template.new(
      ActionView::Template::Sources::File.new(@template_path),
      @template_path,
      ActionView::Template.handler_for_extension(:erb),
      locals: [],
      format: :html
    )
  end

  it '未適用Controllerが先にコンパイルした禁止参照をファイル更新後も拒否する' do
    template = lifecycle_template('<% @hidden = "暗黙の実行結果" %><%= @hidden %>')
    ordinary_view = lifecycle_view(controller_class: TestLifecycleOrdinaryController)
    expect(template.render(ordinary_view, {}).to_s).to eq('暗黙の実行結果')
    File.write(@template_path, '更新後の許可された本文')

    strict_view = lifecycle_view
    expect { template.render(strict_view, {}) }.to raise_error do |error|
      expect([ error, error.cause ]).to include(an_instance_of(StrictViewData::ForbiddenAccessError))
    end
    expect(strict_view.instance_variable_defined?(:@hidden)).to be(false)
  end

  it '有効なコンパイル済みコードは更新後の未実行ファイルの禁止参照に影響されない' do
    template = lifecycle_template('コンパイル時の本文')
    expect(template.render(lifecycle_view, {}).to_s).to eq('コンパイル時の本文')
    File.write(@template_path, '<%= @hidden %>')

    expect(template.render(lifecycle_view, {}).to_s).to eq('コンパイル時の本文')
  end

  it 'コンパイル済みの描画でソースファイルを読み直さない' do
    template = lifecycle_template('繰り返し描画する本文')
    expect(template.render(lifecycle_view, {}).to_s).to eq('繰り返し描画する本文')
    allow(File).to receive(:binread).and_call_original

    3.times do
      expect(template.render(lifecycle_view, {}).to_s).to eq('繰り返し描画する本文')
    end

    expect(File).not_to have_received(:binread).with(@template_path)
  end

  it 'コンパイル失敗後は修正したファイルで同じテンプレートを再試行できる' do
    template = lifecycle_template('<%= 1 + %>')
    ordinary_view = lifecycle_view(controller_class: TestLifecycleOrdinaryController)
    expect { template.render(ordinary_view, {}) }.to raise_error(ActionView::SyntaxErrorInTemplate)
    File.write(@template_path, '<%= view_data.label %>')
    @view_class.include(StrictViewData::Helper)
    strict_view = lifecycle_view
    strict_view.controller.send(:view_data, :label, '再試行の明示値')

    expect(template.render(strict_view, {}).to_s).to eq('再試行の明示値')
  end

  it '共有テンプレートの初回並行描画でもStrict Localsの初期値を失わない' do
    source = '<%# locals: (explicit_text: "明示的な初期値") %><%= explicit_text %>'
    template = ActionView::Template.new(source, @template_path,
      ActionView::Template.handler_for_extension(:erb), locals: [], format: :html)
    views = [ lifecycle_view, lifecycle_view ]
    paused = Queue.new
    resume = Queue.new
    ready = Queue.new
    start = Queue.new
    first_thread = nil
    second_thread = nil
    trace = TracePoint.new(:c_return) do |event|
      next unless Thread.current == first_thread && event.method_id == :sub!
      next unless event.self.is_a?(String) && event.self == '<% %><%= explicit_text %>'

      paused << true
      resume.pop
    end

    begin
      trace.enable
      first_thread = Thread.new do
        start.pop
        template.render(views[0], {}).to_s
      end
      first_thread.report_on_exception = false
      start << true
      Timeout.timeout(5) { paused.pop }
      second_thread = Thread.new do
        ready << true
        template.render(views[1], {}).to_s
      end
      second_thread.report_on_exception = false
      Timeout.timeout(5) { ready.pop }
      second_thread.join(0.2)
      trace.disable
      resume << true

      results = Timeout.timeout(5) { [ first_thread.value, second_thread.value ] }
      expect(results).to eq([ '明示的な初期値', '明示的な初期値' ])
      expect(template.strict_locals?).to eq('explicit_text: "明示的な初期値"')
    ensure
      trace.disable
      resume << true
      [ first_thread, second_thread ].compact.each do |thread|
        thread.kill if thread.alive?
        thread.join
      end
    end
  end
end
