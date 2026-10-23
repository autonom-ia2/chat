require 'rails_helper'

# #2110: o Rails roda o `rescue_from` por fora do `around_action :switch_locale`. O handler tem de ver o idioma do
# pedido, não o padrão.
RSpec.describe ApplicationController, type: :controller do
  controller do
    rescue_from(ArgumentError) { render plain: I18n.locale }

    def index = raise(ArgumentError)
  end

  it 'responde o rescue_from no idioma do pedido' do
    get :index, params: { locale: 'pt_BR' }

    expect(response.body).to eq('pt_BR')
  end
end
