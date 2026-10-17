require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Crm::MemoriaFatos', type: :request do
  include_context 'with crm responsible agent'

  let(:card) { create_card(pipeline: suporte) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/memoria/cards/#{card.id}/fatos" }

  before do
    ligar_memoria!(account)
    CustomAttributeDefinition.create!(account: account, attribute_key: 'placa', attribute_display_name: 'Placa',
                                      attribute_display_type: :text, attribute_model: :card_attribute)
  end

  it 'lista com a procedência, corrige (travado), aceita a sugestão e diz "não vale mais"' do
    sugestao = Crm::Memoria::Gravador.gravar!(account_id: account.id, contact_id: contact.id, escopo: 'card', card_id: card.id, tipo: 'fato',
                                              chave: 'placa', valor: 'SUG1234', fonte: 'cliente', prova_message_ids: [1],
                                              situacao: 'sugestao', gerado_por: 't')

    post base, headers: admin.create_new_auth_token, params: { grupo: 'pedido', chave: 'placa', valor: 'ABC1D23' }, as: :json
    expect(response.parsed_body['payload']).to include('valor' => 'ABC1D23', 'fonte' => 'pessoa_corrigiu', 'travado' => true)

    post "#{base}/#{sugestao.id}/aceitar", headers: admin.create_new_auth_token, as: :json
    novo = response.parsed_body['payload']
    expect(novo).to include('valor' => 'SUG1234', 'versao' => 2)

    post "#{base}/#{novo['id']}/nao_vale_mais", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']['expirado_em']).to be_present

    get base, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'chave fora do catálogo é recusada' do
    post base, headers: admin.create_new_auth_token, params: { grupo: 'pedido', chave: 'inventada', valor: 'x' }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'card de outra conta é 404; sem a flag também' do
    outra = create(:account)
    pipeline = create_crm_pipeline(account: outra, user: create(:user, account: outra)).first
    de_fora = outra.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, contact: create(:contact, account: outra), title: 'X')

    get "/api/v1/accounts/#{account.id}/crm/memoria/cards/#{de_fora.id}/fatos", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    account.disable_features!(Crm::Memoria::FLAG)
    get base, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'o catálogo: só o admin muda cardinalidade e item natural' do
    get "/api/v1/accounts/#{account.id}/crm/memoria/chaves", headers: admin.create_new_auth_token, as: :json
    placa = response.parsed_body['payload'].find { |chave| chave['chave'] == 'placa' }

    patch "/api/v1/accounts/#{account.id}/crm/memoria/chaves/#{placa['id']}", headers: admin.create_new_auth_token,
                                                                              params: { cardinalidade: 'N', item_natural: true }, as: :json
    expect(response.parsed_body['payload']).to include('cardinalidade' => 'N', 'item_natural' => true)

    agente = create(:user, account: account, role: :agent)
    get "/api/v1/accounts/#{account.id}/crm/memoria/chaves", headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
