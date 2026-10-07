# frozen_string_literal: true

require 'prism'

# @note Viewへ明示的に渡す入力だけを管理する。
module StrictViewData
  # @note HAMLとERBを実行せずにRuby構文木へ変換し、暗黙の状態参照を検査する。
  module TemplateCheck
    AMBIENT_METHODS = %i[
      controller helpers assigns view_context local_assigns request response params session cookies
      headers flash action_name controller_name controller_path
    ].freeze
    REFLECTION_METHODS = %i[
      send public_send __send__ method public_method singleton_method binding eval instance_eval
      instance_exec class_eval module_eval instance_variable_get instance_variable_set
      instance_variables remove_instance_variable define_singleton_method try try!
    ].freeze

    # @note テンプレートのRuby構文だけを検査する。文章中のメールアドレスやコメントは対象外とする。
    # @param source [String] テンプレートのソース。
    # @param kind [Symbol] 対応するテンプレート形式。hamlまたはerb。
    # @param identifier [String] エラーに表示するテンプレートの識別名。
    # @param controller_helpers [Array<Symbol, String>] Controllerが公開しているヘルパー名。
    # @param locals_signature [String, nil] Railsが解析したStrict Localsの引数宣言。未指定ならnil。
    # @return [void] 禁止した参照がなければ処理を終了する。
    # @raise [ForbiddenAccessError] 暗黙参照、対応外形式、またはRuby構文の解析失敗がある場合。
    def self.verify!(source, kind:, identifier:, controller_helpers:, locals_signature: nil)
      ruby = compile(source, kind, identifier)
      parsed = Prism.parse("def __strict_view_data_template__(#{locals_signature})\n#{ruby}\nend")
      unless parsed.success?
        raise ForbiddenAccessError, "#{identifier}: テンプレートのRuby構文を解析できません"
      end

      forbidden = AMBIENT_METHODS | controller_helpers.map(&:to_sym)
      nodes = [ parsed.value ]
      until nodes.empty?
        node = nodes.pop
        if node.type.to_s.match?(/\A(?:(?:instance_variable|class_variable|global_variable)_|(?:back_reference|numbered_reference)_read)/)
          raise ForbiddenAccessError, "#{identifier}: @変数・@@変数・グローバル変数は禁止です。view_dataを使用してください"
        end

        if node.respond_to?(:name) && node.name == :view_data &&
           (node.type.to_s.start_with?('local_variable_') || node.type.to_s.include?('parameter') || node.is_a?(Prism::DefNode))
          raise ForbiddenAccessError, "#{identifier}: view_dataの入口をローカル変数やメソッドで上書きできません"
        end

        if node.is_a?(Prism::CallNode)
          direct = node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)
          if (direct && forbidden.include?(node.name)) || REFLECTION_METHODS.include?(node.name)
            raise ForbiddenAccessError, "#{identifier}: #{node.name}の直接参照は禁止です。値をview_dataで渡してください"
          end
        end

        nodes.concat(node.compact_child_nodes)
      end
      return
    end

    # @note 描画用インスタンス変数を生成しないコンパイラで、検査用のRubyを取得する。
    # @param source [String] 実行しないテンプレートのソース。
    # @param kind [Symbol] hamlまたはerb。
    # @param identifier [String] 診断に使うテンプレート識別名。
    # @return [String] 検査用のRubyコード。
    # @raise [ForbiddenAccessError] 対応外の形式を指定した場合。
    def self.compile(source, kind, identifier)
      case kind
      when :erb
        return ActionView::Template::Handlers::ERB::Erubi.new(source, bufvar: '_strict_view_data_buffer').src
      when :haml
        require 'haml'
        return Haml::Engine.new(filename: identifier).call(source)
      else
        raise ForbiddenAccessError, "#{identifier}: 対応していないテンプレート形式です: #{kind.inspect}"
      end
    end
    private_class_method :compile
  end
end
