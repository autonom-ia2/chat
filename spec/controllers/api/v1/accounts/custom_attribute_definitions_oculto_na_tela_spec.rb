require 'rails_helper'

# #2435: o atributo pode sair da tela ("Mostrar na tela" desligado). Cada exemplo diz a falha que pega.
RSpec.describe 'Custom Attribute Definitions API: oculto_na_tela', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:definicao) { create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute') }
  let(:caminho) { "/api/v1/accounts/#{account.id}/custom_attribute_definitions/#{definicao.id}" }

  # MOTIVO: quem administra esconde e mostra de novo; a resposta já traz o estado novo para a tela.
  it 'quem administra esconde e mostra de novo' do
    patch caminho, headers: admin.create_new_auth_token, params: { custom_attribute_definition: { oculto_na_tela: true } }, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['oculto_na_tela']).to be(true)
    expect(definicao.reload.oculto_na_tela).to be(true)

    patch caminho, headers: admin.create_new_auth_token, params: { custom_attribute_definition: { oculto_na_tela: false } }, as: :json

    expect(definicao.reload.oculto_na_tela).to be(false)
  end

  # MOTIVO: agente comum sem a chave de atributos não esconde campo da conta.
  it 'agente comum não muda' do
    patch caminho, headers: agent.create_new_auth_token, params: { custom_attribute_definition: { oculto_na_tela: true } }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(definicao.reload.oculto_na_tela).to be(false)
  end

  # MOTIVO: o atributo escondido continua na API (filtro, automação, IA leem daqui); o novo nasce na tela.
  it 'a lista traz o escondido com o estado, e o atributo novo nasce na tela' do
    definicao.update!(oculto_na_tela: true)

    get "/api/v1/accounts/#{account.id}/custom_attribute_definitions", headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body.find { |item| item['id'] == definicao.id }).to include('oculto_na_tela' => true)

    novo = { attribute_display_name: 'Contador', attribute_key: 'contador', attribute_display_type: 'number',
             attribute_model: 'contact_attribute' }
    post "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
         headers: admin.create_new_auth_token, params: { custom_attribute_definition: novo }, as: :json

    expect(response.parsed_body['oculto_na_tela']).to be(false)
  end
end
