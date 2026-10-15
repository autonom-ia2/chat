require 'rails_helper'

# Autorização do dono para o sistema criar modelos (#1586): estado, ligar e desligar pela tela de Modelos.
RSpec.describe 'Api::V1::Accounts::WhatsappTemplateConsents', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/whatsapp_template_consent" }
  let(:versao) { Whatsapp::Templates::AvisoDeConsentimento::VERSAO }

  before { account.enable_features!('whatsapp_templates_journey') }

  def mudar(user: admin, **params)
    post path, params: { versao_aviso: versao }.merge(params), headers: user.create_new_auth_token, as: :json
  end

  it 'GET: o estado e o aviso com o texto que a tela mostra' do
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['utility']).to eq('ativo' => false, 'mudanca' => nil)
    expect(payload.dig('aviso', 'versao')).to eq(versao)
    expect(payload.dig('aviso', 'textos', 'ligar', 'utility')).to include('mesmo com a conversa aberta')
  end

  it 'POST ligar e desligar: grava as linhas e devolve o estado novo' do
    mudar(operacao: 'ligar', marcas: %w[utility marketing])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'marketing', 'ativo')).to be(true)
    expect(response.parsed_body.dig('payload', 'utility', 'mudanca', 'por')).to eq('Ana Souza')

    mudar(operacao: 'desligar', marcas: %w[utility])

    expect(response.parsed_body.dig('payload', 'utility', 'ativo')).to be(false)
    expect(WhatsappTemplateConsent.where(account: account).count).to eq(4)
  end

  it 'Divulgação sem o Aviso de serviço: 422 com a mensagem' do
    mudar(operacao: 'ligar', marcas: %w[marketing])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'utility_desligada',
                                            'message' => 'A Divulgação só liga com o Aviso de serviço ligado.')
    expect(WhatsappTemplateConsent.count).to eq(0)
  end

  it 'versão do aviso diferente: 409 sem gravar' do
    mudar(operacao: 'ligar', marcas: %w[utility], versao_aviso: 'antiga')

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('aviso_mudou')
    expect(WhatsappTemplateConsent.count).to eq(0)
  end

  it 'agente sem função: não vê nem muda' do
    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    mudar(user: agent, operacao: 'ligar', marcas: %w[utility])
    expect(response).to have_http_status(:unauthorized)
    expect(WhatsappTemplateConsent.count).to eq(0)
  end

  it 'sem a flag da conta: mudar dá 404 sem gravar' do
    account.disable_features!('whatsapp_templates_journey')

    mudar(operacao: 'ligar', marcas: %w[utility])

    expect(response).to have_http_status(:not_found)
    expect(WhatsappTemplateConsent.count).to eq(0)
  end

  it 'sem login: 401' do
    get path, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
