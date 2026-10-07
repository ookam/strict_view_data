# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'action_controller'
require 'action_view'
require 'haml'
require 'haml/rails_template'
require_relative '../lib/strict_view_data'

# @note DBや業務アプリを起動せず、Railsの通常のController描画を検証する。
class TestViewDataController < ActionController::Base
  include StrictViewData::Controller
  before_action :prepare_context
  helper_method :current_user
  layout 'test_view_data'

  # @note 通常の自動描画と検査用テンプレートの明示描画に入力を渡す。
  # @return [void] 入力を登録して描画する。
  def show
    view_data :label, params.fetch(:label, '会話A')
    view_data :current_user, current_user
    render action: params[:page] if params[:page]
  end

  # @note 描画後に登録を変更する異常を再現する。
  # @return [void] 描画後の登録で例外を発生させる。
  def late
    view_data :label, '会話A'
    view_data :current_user, current_user
    render :show
    view_data :extra, '遅すぎる値'
  end

  private

  # @note 既存のbefore_actionが持つ状態をViewへ暗黙に引き継がせないことを検証する。
  # @return [void] Controller内部にだけ状態を設定する。
  def prepare_context
    @hidden = '暗黙の値'
    return
  end

  # @note Controllerヘルパーの直接参照を検出するための値を返す。
  # @return [String] 明示的に渡すユーザー表示値。
  def current_user
    return 'ログイン中'
  end
end

# @note Gemを適用しないControllerの標準描画が変化しないことを検証する。
class TestOrdinaryController < ActionController::Base
  layout false

  # @note 標準のインスタンス変数による描画を行う。
  # @return [void] 通常の描画結果を生成する。
  def show
    @hidden = '標準の値'
    render template: 'test_view_data/forbidden', layout: false
  end
end

RSpec.describe 'Railsの描画との統合', type: :controller do
  before(:all) do
    @root = Dir.mktmpdir('test_view_data_', File.expand_path(__dir__))
    FileUtils.mkdir_p(File.join(@root, 'test_view_data'))
    FileUtils.mkdir_p(File.join(@root, 'layouts'))
    templates = {
      'layouts/test_view_data.html.haml' => "%main\n  = yield\n",
      'test_view_data/show.html.haml' => "%p= view_data.label\n%p= view_data.current_user\n",
      'test_view_data/forbidden.html.haml' => '%p= @hidden',
      'test_view_data/helper.html.haml' => '%p= current_user',
      'test_view_data/missing.html.haml' => '%p= view_data.missing',
      'test_view_data/write.html.haml' => '= view_data(:extra, 1)',
      'test_view_data/partial.html.haml' => '= render "test_view_data/item"',
      'test_view_data/_item.html.haml' => '%p= view_data.label',
      'test_view_data/explicit_user.html.haml' => '= render "test_view_data/user", current_user: "明示したユーザー"',
      'test_view_data/_user.html.haml' => '%p= current_user',
      'test_view_data/explicit_erb_user.html.erb' => '<%= render "test_view_data/erb_user", current_user: "明示したユーザー" %>',
      'test_view_data/_erb_user.html.erb' => '<p><%= current_user %></p>',
      'test_view_data/collection_users.html.haml' => '= render partial: "test_view_data/user", collection: ["明示したユーザー"], as: :current_user',
      'test_view_data/bad_partial.html.haml' => '= render "test_view_data/bad_item"',
      'test_view_data/_bad_item.html.haml' => '%p= @hidden',
      'test_view_data/erb.html.erb' => '<p><%= view_data.label %></p>',
      'test_view_data/bad_erb.html.erb' => '<%= @hidden %>',
      'test_view_data/link.html.haml' => '= link_to "会話", "/rooms"',
      'test_view_data/form.html.erb' => '<%= form_with(url: "/rooms") do |form| %><%= form.text_field :name %><% end %>',
      'test_view_data/shadow.html.haml' => '= render "test_view_data/item", view_data: "別の入力"',
      'test_view_data/strict.html.haml' => "-# locals: (label: '初期値')\n%p= label\n%p= view_data.label",
      'test_view_data/strict_shadow.html.haml' => "-# locals: (view_data: nil)\n%p 表示",
      'test_view_data/strict_hidden.html.haml' => "-# locals: (label: @hidden)\n%p= label",
      'test_view_data/strict_helper.html.erb' => '<%# locals: (label: current_user) %><%= label %>'
    }
    templates.each { |path, source| File.write(File.join(@root, path), source) }
    TestViewDataController.prepend_view_path(@root)
    TestOrdinaryController.prepend_view_path(@root)
  end

  after(:all) do
    FileUtils.remove_entry(@root)
  end

  # @note Rackを通してControllerを呼び、描画結果を返す。
  # @param controller_class [Class] 描画対象のController。
  # @param action [String] 呼び出すアクション名。
  # @param query [Hash] 検査対象のテンプレートや入力を選ぶクエリ。
  # @return [String] 正常に描画されたHTML。
  def render_response(controller_class: TestViewDataController, action: 'show', query: {})
    environment = Rack::MockRequest.env_for("/?#{Rack::Utils.build_query(query)}")
    status, _headers, body = controller_class.action(action).call(environment)
    expect(status).to eq(200)
    output = +''
    body.each { |part| output << part }
    body.close if body.respond_to?(:close)
    return output
  end

  it 'renderを書かずに通常のHAMLとレイアウトを描画する' do
    expect(render_response).to include('<main>', '会話A', 'ログイン中')
  end

  it 'Controllerのインスタンス変数を自動転送しない' do
    controller = TestViewDataController.new
    controller.instance_variable_set(:@hidden, '秘密')
    expect(controller.view_assigns).to eq({})
  end

  it 'before_actionのインスタンス変数を読むと例外になる' do
    expect { render_response(query: { page: 'forbidden' }) }.to raise_error(StrictViewData::ForbiddenAccessError)
  end

  it 'Controllerヘルパーも通常どおり利用できる' do
    expect(render_response(query: { page: 'helper' })).to include('ログイン中')
  end

  it '未登録の入力は描画エラーになる' do
    expect { render_response(query: { page: 'missing' }) }.to raise_error(ActionView::Template::Error, /未登録/)
  end

  it 'View側の登録APIは存在しない' do
    expect { render_response(query: { page: 'write' }) }.to raise_error(ActionView::Template::Error, /wrong number of arguments/)
  end

  it '部分テンプレートに同じ明示的入力を渡す' do
    expect(render_response(query: { page: 'partial' })).to include('会話A')
  end

  %w[explicit_user explicit_erb_user collection_users].each do |page|
    it "ヘルパーと同名のlocalsも明示的に渡せる: #{page}" do
      html = render_response(query: { page: page })
      expect(html).to include('明示したユーザー')
      expect(html).not_to include('ログイン中')
    end
  end

  it '部分テンプレートの暗黙参照も検査する' do
    expect { render_response(query: { page: 'bad_partial' }) }.to raise_error(ActionView::Template::Error, /@変数/)
  end

  it 'ERBでも明示的入力で描画する' do
    expect(render_response(query: { page: 'erb' })).to include('会話A')
  end

  it 'ERBのインスタンス変数を拒否する' do
    expect { render_response(query: { page: 'bad_erb' }) }.to raise_error(StrictViewData::ForbiddenAccessError)
  end

  it '表示用のRailsヘルパーは利用できる' do
    expect(render_response(query: { page: 'link' })).to include('<a href="/rooms">会話</a>')
  end

  it 'ERBのブロック付きフォームも描画できる' do
    expect(render_response(query: { page: 'form' })).to include('<form', 'name="name"')
  end

  it '部分テンプレートのlocalsで入力の入口を上書きできない' do
    expect { render_response(query: { page: 'shadow' }) }.to raise_error(ActionView::Template::Error, /上書き/)
  end

  it 'Strict Localsの明示的な初期値も利用できる' do
    expect(render_response(query: { page: 'strict' })).to include('初期値', '会話A')
  end

  %w[strict_shadow strict_hidden].each do |page|
    it "Strict Localsの初期値でも暗黙参照や上書きを拒否する: #{page}" do
      expect { render_response(query: { page: page }) }.to raise_error(StrictViewData::ForbiddenAccessError)
    end
  end

  it 'Strict Localsの初期値でもヘルパーを利用できる' do
    expect(render_response(query: { page: 'strict_helper' })).to include('ログイン中')
  end

  it '描画開始後の登録を拒否する' do
    expect { render_response(action: 'late') }.to raise_error(StrictViewData::SealedError)
  end

  it '適用していないControllerの描画は変えない' do
    expect(render_response(controller_class: TestOrdinaryController)).to include('標準の値')
  end

  it '通常のControllerが先に描画したテンプレートも検査する' do
    render_response(controller_class: TestOrdinaryController)
    expect { render_response(query: { page: 'forbidden' }) }.to raise_error(StrictViewData::ForbiddenAccessError)
  end

  it '連続したリクエストの入力を共有しない' do
    expect(render_response(query: { label: '一人目' })).to include('一人目')
    html = render_response(query: { label: '二人目' })
    expect(html).to include('二人目')
    expect(html).not_to include('一人目')
  end

  it '同時に描画した別リクエストの値も共有しない' do
    render_response
    threads = 8.times.map do |index|
      Thread.new { render_response(query: { label: "並行#{index}番" }) }
    end
    threads.each_with_index do |thread, index|
      html = thread.value
      expect(html).to include("並行#{index}番")
      expect(html.scan(/並行\d番/)).to eq([ "並行#{index}番" ])
    end
  end

  it '同じコンパイル済みテンプレートは一度だけ解析する' do
    ActionView::LookupContext::DetailsKey.clear
    allow(StrictViewData::TemplateCheck).to receive(:verify!).and_call_original
    render_response
    render_response
    expect(StrictViewData::TemplateCheck).to have_received(:verify!).with(anything, kind: :haml,
      identifier: end_with('/test_view_data/show.html.haml'), locals_signature: nil).once
  end

  it '登録メソッドをルーティング可能なアクションにしない' do
    expect(TestViewDataController.action_methods).not_to include('view_data', 'strict_view_data_values')
  end
end
