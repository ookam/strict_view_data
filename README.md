# strict_view_data

Railsの通常の自動描画を保ちながら、ControllerからViewへ渡す入力を明示します。
公開APIは、登録用の `view_data :名前, 値` と読み取り用の `view_data.名前` だけです。

[GitHub Actions](https://github.com/ookam/strict_view_data/actions/workflows/strict_view_data.yml) で単体テストとGemビルドを実行します。
RubyGemsには未公開です。

## 導入

このリポジトリから利用する場合:

```ruby
# Gemfile
gem 'strict_view_data', git: 'https://github.com/ookam/strict_view_data.git', branch: 'main'
```

```ruby
class ApplicationController < ActionController::Base
  include StrictViewData::Controller
end
```

適用したControllerとその子クラスにだけ有効です。既存Viewを移行する場合は、
対象のControllerにincludeして、そのView・レイアウト・部分テンプレートを一緒に移行してください。
従来の `@変数` を直接参照するViewとは互換性がありません。
`view_data` はRailsのhelperとして登録するため、適用したControllerでは `clear_helpers` を使用しないでください。

## 使い方

```ruby
def show
  view_data :chat_room, @chat_room
  view_data :current_user, current_user
  view_data :loading, false
end
```

```haml
%h1= view_data.chat_room.title
%p= view_data.current_user.name
- if view_data.loading
  %p 読み込み中です
```

`show.html.haml` と通常のレイアウトが自動で選ばれます。ERBも使用できます。
部分テンプレートは、同じリクエストの `view_data` を参照します。
反復処理のブロック変数や、明示的な部分テンプレートのlocalsは利用できます。
Rails標準のhelperやControllerから公開したhelperも利用できます。
自作の業務helperは作らず、業務データはControllerで取得して `view_data` に登録する運用にしてください。

登録は各アクションにまとめます。Gem自体は登録メソッドの呼び出し元がアクションか
コールバックかを判定しません。`before_action` で必要な認証や取得を行っても、
そこで設定した `@変数` は自動的にはViewへ渡りません。

## 固定した契約

- 入力名は小文字のsnake_caseのSymbol。`class`・`send` など既存メソッドと衝突する名前は登録できません。
- 未登録の参照は `MissingValueError`。重複登録は `DuplicateValueError`。
- `nil` と `false` は有効な入力。未登録とは区別します。
- Proc、Method、登録時のブロックは拒否します。取得方法の推論や自動実行はしません。
- 最初のテンプレート描画で登録を閉じ、以後の登録は `SealedError` にします。
- Viewの読み取りAPIは引数・ブロック・代入を受け付けません。
- `view_data` をローカル変数や部分テンプレートのlocalsで上書きできません。
- 入力の対応表はコピーして凍結し、Controllerのインスタンスごとに保持します。
- モデルや配列などの値自体は凍結・複製しません。関連の遅延ロードを止める機能もありません。
  取得を完了させたいコレクションはController側で `to_a` などを使って渡してください。

## 暗黙参照の検査

HAMLまたはERBを実行前にRubyの構文木へ変換し、次を拒否します。

- `@変数`・`@@変数`・グローバル変数を直接書いた読み書き。
- ローカル変数や引数などによる `view_data` の上書き。

レイアウト、部分テンプレート、Strict Localsの初期値も同じ検査を受けます。文章中のメールアドレス、
文字列リテラル、コメント中の `@` は拒否しません。helperやメソッド名による禁止チェックは行いません。

検査には、Railsのコンパイル時に確定したテンプレートソースとStrict Localsの定義を使用します。
テンプレートの再読み込みはRails標準のキャッシュ・リロード設定に従います。
違反時のメッセージには対象テンプレートを含めます。

これはアプリ内の入力契約を検査する仕組みであり、任意のRubyを隔離するサンドボックスではありません。
helper内部の処理、渡したモデルのメソッド、反射を使ったアクセス、定数を経由したDBアクセスまで
解析・禁止する機能はありません。業務データをControllerで取得して渡す方針は開発規約で守ってください。
入力キーの未使用検査、型検査、深い凍結も対象外です。

## 対応環境

- Ruby 3.2以上、RailsのAction Pack / Action View 8.1系。
- Rails標準の `ActionView::Template` とERBハンドラー、HAML 6.3系の標準Railsハンドラー。
- 実行確認: Ruby 3.4.5 / Rails 8.1.4 / HAML 6.3.0・6.3.1。
- 対応外のテンプレートハンドラーは無検査で通さず、描画時に例外にします。

HAMLを使うアプリは `gem 'haml', '~> 6.3.0'` を追加してください。
HAMLを使わないアプリにHAMLの依存は追加しません。

## 開発・検証

Ruby 3.2以上の環境で、このリポジトリをcloneして実行します。

```sh
git clone https://github.com/ookam/strict_view_data.git
cd strict_view_data
bundle install
bundle exec rake
gem build strict_view_data.gemspec
```

回帰テストは `tmp/test_*_spec.rb` です。生成fixtureだけが一時ファイルです。
DB、AWS、ホストアプリの起動は不要です。RSpecの通常の描画検証に加え、
レイアウト・部分テンプレート・未適用Controller・連続/並行リクエストも検査します。
`.github/workflows/strict_view_data.yml` はRuby 3.2と3.4でテストとGemビルドを行う設定です。
ローカルで実行したRubyは3.4.5です。CIの実行結果はGitHub Actionsで確認してください。

ソースはこのGitHubリポジトリで管理します。ライセンスは未設定で、RubyGemsへの公開は行っていません。
