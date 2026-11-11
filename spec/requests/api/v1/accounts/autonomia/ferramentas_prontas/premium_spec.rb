require 'rails_helper'

# #2858 F7 — os cards Premium na API da vitrine: aparecem só com a flag do Premium, cada um com as 20 grátis, quantas
# restam à conta e os preços depois delas; o "Experimente" não roda consulta paga; o "Incluir" recusa sem a flag. Nada
# técnico na resposta (nem dataset, nem rota, nem custo).
RSpec.describe 'Vitrine de ferramentas prontas: Premium', type: :request do
  include FerramentasProntasHelper

  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:outra_conta) { create(:account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom') }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/ferramentas_prontas" }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:premium) { %w[certidoes_empresa raio_x_empresa conferir_pessoa historico_placa risco_endereco imovel_rural contato_empresa] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    ligar_premium(account)
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE)
  end

  def fontes
    get base, headers: admin.create_new_auth_token, as: :json
    response.parsed_body['fontes'].index_by { |fonte| fonte['chave'] }
  end

  it 'mostra os 7 cards com as grátis que restam no mês e os preços; um card não mexe no do outro, nem outra conta' do
    saldo_premium!(account, 'certidoes_empresa', 5)
    saldo_premium!(outra_conta, 'raio_x_empresa', 20)
    # O mês passado não conta: as 20 grátis renovam todo mês.
    saldo_premium!(account, 'raio_x_empresa', 20, mes: Autonomia::FerramentasProntas::Premium.mes_da_conta(account).prev_month)

    lista = fontes

    expect(lista.keys).to include(*premium)
    expect(lista['certidoes_empresa']['premium']).to eq('gratis' => 20, 'restantes' => 15, 'precos' => %w[0.06 0.15])
    expect(lista['raio_x_empresa']['premium']).to eq('gratis' => 20, 'restantes' => 20, 'precos' => %w[0.09 0.12])
    expect(lista['historico_placa']['premium']).to eq('gratis' => 20, 'restantes' => 20, 'precos' => %w[0.09])
    expect(lista['imovel_rural']['premium']['precos']).to eq(%w[0.15 0.23])
    expect(lista['cep']).not_to have_key('premium')
    expect(response.body).not_to include('ondemand', 'bigdatacorp', 'custo')
  end

  it 'passadas as 20, restam 0 (nunca negativo)' do
    saldo_premium!(account, 'historico_placa', 27)

    expect(fontes['historico_placa']['premium']['restantes']).to eq(0)
  end

  it 'sem a flag do Premium, os cards somem e o "Incluir" recusa; as grátis seguem' do
    account.disable_features!(Autonomia::FerramentasProntas::Premium::FLAG)

    expect(fontes.keys).not_to include(*premium)
    expect(fontes.keys).to include('cep')
    post "#{base}/incluir", params: { fonte: 'certidoes_empresa', agent_id: agent.id, usar_quando: 'pedirem certidão' },
                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['motivo']).to eq('desligada')
  end

  it 'o "Incluir" de um card Premium funciona com a flag, e o "Experimente" não consulta' do
    post "#{base}/incluir", params: { fonte: 'certidoes_empresa', agent_id: agent.id, usar_quando: 'pedirem certidão' },
                            headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)

    post "#{base}/experimentar", params: { fonte: 'certidoes_empresa', valor: '11222333000181' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('situacao' => 'premium')
    expect(chamou_a_bigdatacorp?).to be(false)
  end
end
