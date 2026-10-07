# frozen_string_literal: true

require 'haml'
require_relative '../lib/strict_view_data'

RSpec.describe 'テンプレートの暗黙参照の禁止' do
  [
    [ '%p= @room', :haml ],
    [ '- @room = 1', :haml ],
    [ '%p= defined?(@room)', :haml ],
    [ '%p= "#{@room}"', :haml ],
    [ '%p #{@room}', :haml ],
    [ '%div{class: @room} 本文', :haml ],
    [ '%p= @@room', :haml ],
    [ '%p= $room', :haml ],
    [ '%p= $1', :haml ],
    [ '%p= $&', :haml ],
    [ '<%= @output_buffer %>', :erb ],
    [ '<%= @room %>', :erb ],
    [ '<% @room = 1 %>', :erb ],
    [ '<%= "#{@room}" %>', :erb ],
    [ "- view_data = {}\n%p= view_data", :haml ],
    [ "- [1].each do |view_data|\n  %p= view_data", :haml ],
    [ '<% view_data = {} %>', :erb ]
  ].each do |source, kind|
    it "#{kind}の暗黙参照を拒否する: #{source}" do
      expect do
        StrictViewData::TemplateCheck.verify!(source, kind: kind, identifier: 'test/show')
      end.to raise_error(StrictViewData::ForbiddenAccessError, /test\/show/)
    end
  end

  [
    [ '%p= current_user.name', :haml ],
    [ '%p= self.current_user.name', :haml ],
    [ '%p= params[:name]', :haml ],
    [ '%p= controller.current_user', :haml ],
    [ '%p= helpers.current_user', :haml ],
    [ '%p= request.path', :haml ],
    [ '%p= session[:name]', :haml ],
    [ '%p= view_data.send(:current_user)', :haml ],
    [ '%p= public_send(:current_user)', :haml ],
    [ '%p= eval("@room")', :haml ],
    [ '%p= instance_variable_get(:@room)', :haml ],
    [ '%p= binding', :haml ],
    [ '%p= view_data.try(:missing)', :haml ],
    [ '%p= view_data.current_user.name', :haml ],
    [ '%p= link_to("会話", "/rooms")', :haml ],
    [ '%p example@example.com', :haml ],
    [ '%p= "@room は文字列です"', :haml ],
    [ "-# @room はコメントです\n%p 本文", :haml ],
    [ '%div{class: "card"} 本文', :haml ],
    [ "- view_data.messages.each do |message|\n  %p= message.body", :haml ],
    [ '<%= view_data.current_user.name %>', :erb ],
    [ 'example@example.com <%# @room %>', :erb ],
    [ '<%== view_data.label %>', :erb ],
    [ '<%= form_with(url: "/rooms") do |form| %><%= form.text_field :name %><% end %>', :erb ],
    [ "= form_with(url: '/rooms') do |form|\n  = form.text_field :name", :haml ]
  ].each do |source, kind|
    it "#{kind}の明示的入力や表示文字列を許可する: #{source}" do
      expect do
        StrictViewData::TemplateCheck.verify!(source, kind: kind, identifier: 'test/show')
      end.not_to raise_error
    end
  end

  it '対応外のテンプレートを無検査で通さない' do
    expect do
      StrictViewData::TemplateCheck.verify!('xml.title @room', kind: :builder, identifier: 'test/show')
    end.to raise_error(StrictViewData::ForbiddenAccessError, /対応していない/)
  end

  it '壊れたRubyを無検査で通さない' do
    expect do
      StrictViewData::TemplateCheck.verify!('<%= ( %>', kind: :erb, identifier: 'test/show')
    end.to raise_error(StrictViewData::ForbiddenAccessError, /構文/)
  end
end
