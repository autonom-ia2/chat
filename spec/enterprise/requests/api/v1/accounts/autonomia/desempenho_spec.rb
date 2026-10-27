require 'rails_helper'

# Painel de desempenho do agente pela API (#2251): flag da conta, chave desempenho_view (função personalizada),
# robô de outro sistema preso à conta, exportação e as conversas de caixas que a pessoa não vê. Loja inventada.
RSpec.describe 'Autonomia agent performance panel', type: :request do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }).tap do |conta|
      conta.enable_features!('agentes_painel_desempenho')
    end
  end
  let(:robo) { create(:agent_bot, account: account) }
  let(:caixa) { create(:inbox, account: account) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: caixa) }
  let(:escondida) { create(:conversation, account: account, inbox: outra_caixa) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:endereco) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{robo.id}/desempenho" }

  def com_funcao(permissoes)
    create(:user, account: account, role: :agent).tap do |usuario|
      funcao = create(:custom_role, account: account, permissions: permissoes)
      usuario.account_users.find_by(account: account).update!(custom_role: funcao)
    end
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    ficha_da_loja!(account, sujeito_id: robo.id)
    procura_da_loja!(conversa, sujeito_id: robo.id, inicio: '2026-10-20 10:00')
    procura_da_loja!(escondida, sujeito_id: robo.id, inicio: '2026-10-21 10:00', perda_evitavel: true, motivo_ids: ['sem_estoque'])
    leitura_da_loja!(conversa, sujeito_id: robo.id, ate: '2026-10-21 18:00')
    leitura_da_loja!(escondida, sujeito_id: robo.id, ate: '2026-10-21 18:00')
  end

  it 'answers 404 with the account flag off' do
    account.disable_features!('agentes_painel_desempenho')

    get endereco, params: { origem: 'webhook', periodo: '7' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'gives the admin the whole panel of the period, with every conversation open' do
    get endereco, params: { origem: 'webhook', periodo: '7' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    corpo = response.parsed_body
    expect(corpo['meta']).to include('fonte' => 'api', 'periodo' => include('chave' => '7'))
    expect(corpo['procuras'].pluck('conversa')).to contain_exactly(conversa.display_id, escondida.display_id)
    expect(corpo['procuras'].pluck('visivel').uniq).to eq([nil])
  end

  it 'refuses an agent without the desempenho_view key, even with autonomia_view' do
    get endereco, params: { origem: 'webhook' }, headers: com_funcao(['autonomia_view']).create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'counts only the inboxes the person sees, with nothing from the hidden ones (ESPEC 6.2)' do
    usuario = com_funcao(%w[desempenho_view conversation_view])
    create(:inbox_member, user: usuario, inbox: caixa)

    get endereco, params: { origem: 'webhook', periodo: '7' }, headers: usuario.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    corpo = response.parsed_body
    kpis = corpo['kpis'].to_h { |kpi| [kpi['id'], kpi['valor']] }
    expect(kpis).to include('procuras' => 1, 'conversas' => 1, 'perdas_evitaveis' => 0)
    expect(corpo['procuras'].pluck('conversa')).to eq([conversa.display_id])
    expect(corpo['perdas']['lista']).to be_empty
    expect(corpo['recomendacoes']).to eq([])
    expect(corpo.dig('meta', 'visibilidade')).to include('escopo' => 'caixas', 'ocultas' => 1)
  end

  it 'gives the admin the totals of the whole account' do
    get endereco, params: { origem: 'webhook', periodo: '7' }, headers: admin.create_new_auth_token, as: :json

    kpis = response.parsed_body['kpis'].to_h { |kpi| [kpi['id'], kpi['valor']] }
    expect(kpis).to include('procuras' => 2, 'conversas' => 2, 'perdas_evitaveis' => 1)
    expect(response.parsed_body.dig('meta', 'visibilidade', 'escopo')).to eq('conta')
  end

  it 'returns the empty panel when the person sees none of the read conversations' do
    get endereco, params: { origem: 'webhook', periodo: '7' }, headers: com_funcao(['desempenho_view']).create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('vazio' => true, 'meta' => include('situacao' => 'sem_conversas',
                                                                               'visibilidade' => include('ocultas' => 2)))
    expect(response.parsed_body).not_to have_key('procuras')
  end

  it 'leaves the money out for a role without sales_value_view, and in for one with it (seeing every inbox)' do
    ticket = { 'com_valor' => 3, 'medio' => 100.0, 'mediano' => 90.0, 'moeda' => 'BRL', 'nota' => nil }
    Autonomia::Desempenho::Ficha.last.update!(referencias: { 'ticket' => ticket, 'confianca' => nil, 'exemplos' => {} })

    base = %w[desempenho_view conversation_view]
    sem_valor, com_valor = [[], ['sales_value_view']].map do |extra|
      com_funcao(base + extra).tap do |usuario|
        [caixa, outra_caixa].each { |inbox| create(:inbox_member, user: usuario, inbox: inbox) }
      end
    end

    get endereco, params: { origem: 'webhook' }, headers: sem_valor.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('ticket' => nil, 'kpis' => be_present)

    get endereco, params: { origem: 'webhook' }, headers: com_valor.create_new_auth_token, as: :json
    expect(response.parsed_body['ticket']).to include('mediano' => 90.0)
  end

  it 'never reads a bot from another account' do
    de_fora = create(:agent_bot, account: create(:account))

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{de_fora.id}/desempenho", params: { origem: 'webhook' },
                                                                                    headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'never reads our agent from another account nor the system agent' do
    de_fora = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Outra', agent_type: 'support', status: :active,
                                               instruction: 'Atende outra loja.')
    do_sistema = Autonomia::Agents::Agent.create!(account: account, name: 'Guia', agent_type: 'support', status: :active,
                                                  instruction: 'Guia.', config: { 'system_key' => 'guia' })

    [de_fora, do_sistema].each do |agente|
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}/desempenho", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  it 'returns the empty panel with leitura_desligada when the agent has no reading' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Atendente', agent_type: 'support', status: :active,
                                              instruction: 'Você atende a loja.')

    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}/desempenho", params: { periodo: '90' },
                                                                                   headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('vazio' => true,
                                            'meta' => include('situacao' => 'leitura_desligada', 'periodo' => { 'chave' => '90' }))
  end

  describe 'export' do
    let(:exportar) { "#{endereco}/exportar" }

    it 'sends the PDF and the spreadsheet of the period' do
      get exportar, params: { origem: 'webhook', periodo: '7', formato: 'pdf' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
      expect(response.body).to start_with('%PDF')
      expect(response.headers['Content-Disposition']).to include('desempenho-7.pdf')

      get exportar, params: { origem: 'webhook', periodo: '7', formato: 'xlsx' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      expect(response.body).to start_with('PK')
    end

    it 'refuses an unknown format' do
      get exportar, params: { origem: 'webhook', formato: 'csv' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'leaves the conversations of hidden inboxes out of the file too' do
      usuario = com_funcao(%w[desempenho_view conversation_view contact_export])
      create(:inbox_member, user: usuario, inbox: caixa)
      Autonomia::Desempenho::Procura.find_by(conversation: escondida).update!(dados: { 'resumo' => 'Texto que não pode sair.' })

      get exportar, params: { origem: 'webhook', periodo: '7', formato: 'xlsx' }, headers: usuario.create_new_auth_token

      expect(response).to have_http_status(:ok)
      planilha = Roo::Excelx.new(StringIO.new(response.body))
      textos = planilha.sheets.flat_map { |aba| planilha.sheet(aba).to_a.flatten.compact.map(&:to_s) }
      expect(textos.join(' ')).not_to include('Texto que não pode sair.')
    end

    it 'needs desempenho_view and contact_export together (ESPEC 6.3)' do
      [%w[desempenho_view conversation_view], %w[contact_export conversation_view]].each do |permissoes|
        get exportar, params: { origem: 'webhook', formato: 'pdf' }, headers: com_funcao(permissoes).create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end

      usuario = com_funcao(%w[desempenho_view contact_export conversation_view])
      create(:inbox_member, user: usuario, inbox: caixa)
      get exportar, params: { origem: 'webhook', formato: 'pdf' }, headers: usuario.create_new_auth_token

      expect(response).to have_http_status(:ok)
    end
  end
end
