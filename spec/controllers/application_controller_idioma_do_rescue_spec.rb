require 'rails_helper'

# #2110: o Rails roda o `rescue_from` por fora do `around_action :switch_locale`. O handler tem de ver o idioma do
# pedido, não o padrão, e o idioma não pode ficar no processo depois do pedido, nem quando o próprio handler falha.
RSpec.describe ApplicationController, type: :controller do
  controller do
    rescue_from(ArgumentError) { render plain: I18n.locale }
    rescue_from(KeyError) { raise IndexError }

    def index = raise(ArgumentError)

    def show = raise(KeyError)
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'show' => 'anonymous#show'
    end
  end

  it 'responde o rescue_from no idioma do pedido e devolve o idioma padrão depois' do
    get :index, params: { locale: 'pt_BR' }

    expect(response.body).to eq('pt_BR')
    expect(I18n.locale).to eq(I18n.default_locale)
  end

  it 'devolve o idioma padrão mesmo quando o handler levanta erro' do
    expect { get :show, params: { locale: 'pt_BR' } }.to raise_error(IndexError)

    expect(I18n.locale).to eq(I18n.default_locale)
  end
end
