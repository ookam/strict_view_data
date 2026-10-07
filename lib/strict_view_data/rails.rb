# frozen_string_literal: true

require 'action_controller'
require 'action_view'

# @note Viewへ明示的に渡す入力だけを管理する。
module StrictViewData
  # @note Viewには引数なしの読み取りAPIだけを公開する。
  module Helper
    # @note Controllerで登録済みの入力を読み取る。登録用の引数は受け取らない。
    # @return [Values] このリクエストに固定されたView入力。
    def view_data
      return controller.send(:strict_view_data_values)
    end
  end

  # @note 適用したControllerだけで明示的入力を有効にし、暗黙の変数転送を止める。
  module Controller
    extend ActiveSupport::Concern
    include Registration

    included do
      helper Helper
    end

    # @note RailsがControllerのインスタンス変数をViewへ複製する経路を閉じる。
    # @return [Hash] 常に空の対応。入力はview_dataからのみ提供する。
    def view_assigns
      return {}
    end
  end

  # @note 適用対象の描画時に、レイアウトと部分テンプレートも含めて暗黙参照を検査する。
  module TemplateGuard
    # @note コンパイルした本文だけを検査し、描画前に入力を固定する。コンパイル済みの描画ではファイルを読み直さない。
    # @param view [ActionView::Base] 描画するViewのコンテキスト。
    # @param locals [Hash] Railsが提供するローカル変数。
    # @param buffer [ActionView::OutputBuffer, nil] Railsの出力先。nilならRailsに生成を委ねる。
    # @param implicit_locals [Array<Symbol>] Railsの暗黙ローカル変数名。
    # @param add_to_stack [Boolean] Railsの描画スタックに記録する場合はtrue。
    # @param block [Proc, nil] レイアウトなどへ渡す描画ブロック。未指定ならnil。
    # @return [Object] Railsの描画結果。
    # @raise [ForbiddenAccessError] テンプレートが暗黙参照を含む、または検査できない場合。
    def render(view, locals, buffer = nil, implicit_locals: [], add_to_stack: true, &block)
      controller = view.respond_to?(:controller) ? view.controller : nil
      if controller.is_a?(Controller)
        if locals.key?(:view_data) || locals.key?('view_data')
          raise ForbiddenAccessError, "#{identifier}: localsでview_dataを上書きできません"
        end
        kind = strict_view_data_template_kind
        raise ForbiddenAccessError, "#{identifier}: 対応していないテンプレート形式です" unless kind

        compile!(view)
        unless @_strict_view_data_snapshot
          raise ForbiddenAccessError, "#{identifier}: コンパイル時のテンプレートを検査できません"
        end
        unless @_strict_view_data_checked
          compiled_source, locals_signature = @_strict_view_data_snapshot
          TemplateCheck.verify!(compiled_source, kind: kind, identifier: identifier, locals_signature: locals_signature)
          @_strict_view_data_checked = true
        end
        controller.send(:strict_view_data_values)
      end

      return super(view, locals, buffer, implicit_locals: implicit_locals, add_to_stack: add_to_stack, &block)
    end

    private

    # @note Railsのコンパイルロック内で本文を固定し、成功した本文とStrict Localsだけを保存する。
    #   未適用Controllerが先に描画した場合も保存する。元のソースは必ず復元し、失敗後の再試行を妨げない。
    # @param mod [Module] Railsが描画メソッドを定義する先。
    # @return [Array<Symbol>, nil] Railsが返すStrict Localsのキー。通常のテンプレートなどではnil。
    def compile(mod)
      return super unless strict_view_data_template_kind

      original_source = @source
      begin
        @source = source.dup
        result = super
        @_strict_view_data_snapshot = [ source.dup.freeze, strict_locals?&.dup&.freeze ].freeze
        return result
      ensure
        @source = original_source
      end
    end

    # @note 検査したコンパイラと一致する標準のERBまたはHAMLハンドラーを識別する。
    # @return [Symbol, nil] 対応形式の名前。対応外ならnilとして検査エラーにする。
    def strict_view_data_template_kind
      return :erb if handler.instance_of?(ActionView::Template::Handlers::ERB)
      return :haml if defined?(Haml::RailsTemplate) && handler.instance_of?(Haml::RailsTemplate)

      return nil
    end
  end
end

ActionView::Template.prepend(StrictViewData::TemplateGuard)
