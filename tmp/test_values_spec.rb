# frozen_string_literal: true

require_relative '../lib/strict_view_data'

RSpec.describe 'View入力の登録と読み取り' do
  # @note RailsなしでControllerの登録APIを検査する。
  class TestViewDataWriter
    include StrictViewData::Registration
  end

  let(:writer) { TestViewDataWriter.new }

  it '登録したオブジェクトをそのまま返す' do
    object = Object.new
    writer.send(:view_data, :room, object)
    expect(writer.send(:strict_view_data_values).room).to equal(object)
  end

  it '明示的なnilとfalseを保持する' do
    writer.send(:view_data, :empty, nil)
    writer.send(:view_data, :loading, false)
    values = writer.send(:strict_view_data_values)
    expect(values.empty).to be_nil
    expect(values.loading).to be(false)
  end

  it '未登録名をnilにせず例外にする' do
    expect { writer.send(:strict_view_data_values).missing }.to raise_error(StrictViewData::MissingValueError)
  end

  it 'nilを登録した名前も重複登録できない' do
    writer.send(:view_data, :room, nil)
    expect { writer.send(:view_data, :room, '次') }.to raise_error(StrictViewData::DuplicateValueError)
  end

  [ 'room', :Room, :room?, :room=, :_room, :class, :send, :freeze, :respond_to?, :method_missing ].each do |name|
    it "不正または衝突する名前#{name.inspect}を登録できない" do
      expect { writer.send(:view_data, name, '値') }.to raise_error(StrictViewData::InvalidNameError)
    end
  end

  it 'Procを登録できない' do
    expect { writer.send(:view_data, :lazy, -> { raise '実行されない' }) }.to raise_error(ArgumentError)
  end

  it 'Methodを登録できない' do
    expect { writer.send(:view_data, :lazy, '値'.method(:upcase)) }.to raise_error(ArgumentError)
  end

  it '登録時にブロックを黙って捨てない' do
    expect { writer.send(:view_data, :room, '値') { '別の値' } }.to raise_error(ArgumentError)
  end

  it '入力オブジェクト自体を凍結してモデルの挙動を変えない' do
    object = [ '値' ]
    writer.send(:view_data, :items, object)
    writer.send(:strict_view_data_values)
    expect(object).not_to be_frozen
  end

  it 'callに応答する値を勝手に実行しない' do
    callable = double('値', call: '実行結果')
    expect(callable).not_to receive(:call)
    writer.send(:view_data, :object, callable)
    expect(writer.send(:strict_view_data_values).object).to equal(callable)
  end

  it '読み取りを開始した後は登録を増やせない' do
    values = writer.send(:strict_view_data_values)
    expect(values).to be_frozen
    expect { writer.send(:view_data, :late, 1) }.to raise_error(StrictViewData::SealedError)
  end

  it 'ドットアクセスに引数やブロックを渡せない' do
    writer.send(:view_data, :room, '値')
    values = writer.send(:strict_view_data_values)
    expect { values.room('別') }.to raise_error(ArgumentError)
    expect { values.room(other: true) }.to raise_error(ArgumentError)
    expect { values.room { '別' } }.to raise_error(ArgumentError)
  end

  it '値を書き換えるアクセサーを公開しない' do
    writer.send(:view_data, :room, '値')
    expect { writer.send(:strict_view_data_values).room = '別' }.to raise_error(ArgumentError)
  end

  it '存在確認と実際のキーが一致する' do
    writer.send(:view_data, :room, nil)
    values = writer.send(:strict_view_data_values)
    expect(values.respond_to?(:room)).to be(true)
    expect(values.respond_to?(:missing)).to be(false)
  end

  it '登録APIをControllerの公開アクションにしない' do
    expect(writer.respond_to?(:view_data)).to be(false)
    expect(writer.respond_to?(:strict_view_data_values)).to be(false)
  end

  it '別のリクエストに値が混ざらない' do
    other = TestViewDataWriter.new
    writer.send(:view_data, :room, '自分')
    other.send(:view_data, :room, '別人')
    expect(writer.send(:strict_view_data_values).room).to eq('自分')
    expect(other.send(:strict_view_data_values).room).to eq('別人')
  end
end
