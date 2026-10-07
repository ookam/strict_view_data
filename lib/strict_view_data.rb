# frozen_string_literal: true

# @note Viewへ明示的に渡す入力だけを管理する。
module StrictViewData
  VERSION = '0.1.0'

  # @note ドットアクセスで安全に表現できない登録名を示す。
  class InvalidNameError < ArgumentError; end

  # @note 同じ入力の二重登録を示す。
  class DuplicateValueError < ArgumentError; end

  # @note 明示的に登録されていない入力の参照を示す。
  class MissingValueError < KeyError; end

  # @note 描画開始後に入力を追加しようとしたことを示す。
  class SealedError < StandardError; end

  # @note テンプレートが暗黙の状態にアクセスしたことを示す。
  class ForbiddenAccessError < StandardError; end

  # @note 名前と値の対応を固定して読み取り専用の入口を提供する。値自体の深い凍結は行わない。
  class Values
    # @note 登録名の形式と既存メソッドとの衝突を検査する。
    # @param name [Symbol] 小文字のsnake_caseで表す入力名。
    # @return [void] 正常な入力名なら処理を終了する。
    # @raise [InvalidNameError] 入力名が不正、または既存メソッドと衝突する場合。
    def self.validate_name!(name)
      valid = name.is_a?(Symbol) && name.to_s.match?(/\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*\z/)
      collision = valid && (method_defined?(name) || private_method_defined?(name))
      raise InvalidNameError, "登録できない入力名です: #{name.inspect}" unless valid && !collision

      return
    end

    # @note 登録済みの対応を複製して凍結する。モデルなどの値は同じ実体を保持する。
    # @param entries [Hash<Symbol, Object>] 検査済みの入力。nilやfalseも値として保持する。
    # @return [void] 読み取り専用の対応を初期化する。
    def initialize(entries)
      @entries = entries.dup.freeze
      freeze
      return
    end

    private

    # @note 引数なしのドットアクセスだけを入力の参照として扱う。
    # @param name [Symbol] 参照する入力名。
    # @param arguments [Array<Object>] 使用を許可しない位置引数。
    # @param keywords [Hash] 使用を許可しないキーワード引数。
    # @param block [Proc, nil] 使用を許可しないブロック。通常はnil。
    # @return [Object, nil] 登録された値そのもの。
    # @raise [ArgumentError] 引数またはブロックを渡した場合。
    # @raise [MissingValueError] 入力が登録されていない場合。
    def method_missing(name, *arguments, **keywords, &block)
      unless arguments.empty? && keywords.empty? && block.nil?
        raise ArgumentError, 'view_dataの参照には引数やブロックを渡せません'
      end

      return @entries.fetch(name) { raise MissingValueError, "未登録のView入力です: #{name}" }
    end

    # @note 登録済みの名前に限り動的な読み取りに応答する。
    # @param name [Symbol] 存在確認する入力名。
    # @param include_private [Boolean] Rubyが指定する非公開メソッドの検索条件。
    # @return [Boolean] 入力が存在する場合、または標準の応答条件を満たす場合はtrue。
    def respond_to_missing?(name, include_private = false)
      return @entries.key?(name) || super
    end
  end

  # @note リクエストのControllerにだけ入力を保持し、最初の読み取りで登録を閉じる。
  module Registration
    private

    # @note 入力を明示的に登録する。取得処理やProcの自動実行は行わない。
    # @param name [Symbol] Viewで参照する入力名。
    # @param object [Object, nil] その場で決めた値。nilやfalseも明示的な入力として許可する。
    # @param block [Proc, nil] 登録では使用を許可しないブロック。通常はnil。
    # @return [void] 名前と値を登録する。
    # @raise [InvalidNameError] 入力名が不正、または既存メソッドと衝突する場合。
    # @raise [DuplicateValueError] 同じ名前を二度登録した場合。
    # @raise [SealedError] 描画開始後に登録した場合。
    # @raise [ArgumentError] Proc、Method、またはブロックを渡した場合。
    def view_data(name, object, &block)
      raise SealedError, '描画開始後はView入力を登録できません' if @_strict_view_data_values
      raise ArgumentError, 'view_dataの登録にブロックは渡せません' if block

      Values.validate_name!(name)
      raise ArgumentError, 'ProcやMethodではなく、取得済みの値を渡してください' if object.is_a?(Proc) || object.is_a?(Method)

      entries = (@_strict_view_data_entries ||= {})
      raise DuplicateValueError, "View入力が重複しています: #{name}" if entries.key?(name)

      entries[name] = object
      return
    end

    # @note 描画中に入力が変化しないよう、読み取り専用の対応を一度だけ作る。
    # @return [Values] このControllerだけの入力。登録がなければ空の入力。
    def strict_view_data_values
      return @_strict_view_data_values ||= Values.new(@_strict_view_data_entries || {})
    end
  end
end

require_relative 'strict_view_data/template_check'
require_relative 'strict_view_data/rails'
