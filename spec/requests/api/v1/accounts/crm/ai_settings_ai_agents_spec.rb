require 'rails_helper'

# #1593 — a Atribuição do funil com agentes de IA: a lista `ai_agents` (só com a Fase 2) e "A mesma pessoa" apontando
# um agente (pool_type 'ai_agent'). Quem pode receber é a regra real dos Agentes (Lia atende as duas caixas do funil).
RSpec.describe 'CRM AI settings: agentes de IA na Atribuição', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { funil.first }
  let(:stage) { funil.last }
  let(:vendas) { create(:inbox, account: account, name: 'WhatsApp Vendas') }
  let(:contato) { create(:inbox, account: account, name: 'E-mail Contato') }
  let(:lia) { criar_agente_ia(account, 'Lia') }
  let(:marta) { criar_agente_ia(account, 'Marta') }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings" }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run } }

  before do
    [vendas, contato].each { |inbox| pipeline.pipeline_inboxes.create!(account: account, inbox: inbox) }
    ligar_agentes_ia!(account)
    [vendas, contato].each { |inbox| agente_na_caixa!(lia, inbox) }
  end

  def salvar(handoff, stage_handoff: nil)
    params = { ai_settings: { handoff: handoff } }
    params[:stage_handoff] = stage_handoff if stage_handoff
    patch url, params: params, headers: admin.create_new_auth_token, as: :json
  end

  # Pega: a tela de "Quem recebe" sem os agentes, ou com eles sem as caixas em que trabalham.
  it 'lista os agentes que podem receber, com as caixas do funil em que cada um trabalha' do
    get url, headers: admin.create_new_auth_token

    expect(response.parsed_body.dig('payload', 'ai_agents')).to eq(
      [{ 'id' => lia.id, 'name' => 'Lia', 'parado' => false,
         'caixas' => [{ 'id' => contato.id, 'name' => 'E-mail Contato' }, { 'id' => vendas.id, 'name' => 'WhatsApp Vendas' }] }]
    )
  end

  # Pega: o agente escolhido que parou sumir da tela (sem o aviso de que a conversa está indo para a equipe).
  it 'o agente escolhido que não pode mais receber vem marcado parado' do
    salvar({ enabled: true, pool_type: 'ai_agent', pool_id: marta.id })

    agentes = response.parsed_body.dig('payload', 'ai_agents')

    expect(agentes).to include({ 'id' => marta.id, 'name' => 'Marta', 'parado' => true, 'caixas' => [] })
  end

  it 'sem a Fase 2: a chave não vem, e a tela mostra só pessoas' do
    Autonomia::Agents::Fase2.desligar!(account)

    get url, headers: admin.create_new_auth_token

    expect(response.parsed_body['payload']).not_to have_key('ai_agents')
  end

  it 'salva "A mesma pessoa" apontando a Lia, no funil e numa etapa', :aggregate_failures do
    salvar({ enabled: true, pool_type: 'ai_agent', pool_id: lia.id },
           stage_handoff: { stage.id.to_s => { custom: true, enabled: true, pool_type: 'ai_agent', pool_id: lia.id } })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'handoff')).to include('pool_type' => 'ai_agent', 'pool_id' => lia.id)
    expect(stage.reload.metadata['ai_handoff']).to include('pool_type' => 'ai_agent', 'pool_id' => lia.id)
  end

  # Pega: apontar para agente de outra conta, interno (Copiloto) ou inexistente.
  it 'recusa agente de outra conta, interno ou sem id', :aggregate_failures do
    alheio = criar_agente_ia(create(:account), 'Alheio')
    copiloto = criar_agente_ia(account, 'Copiloto').tap { |agente| agente.update_columns(actuation: 1) } # rubocop:disable Rails/SkipsModelValidations

    [alheio.id, copiloto.id, nil].each do |pool_id|
      salvar({ enabled: true, pool_type: 'ai_agent', pool_id: pool_id })
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(pipeline.reload.metadata.dig('ai', 'handoff', 'pool_type')).not_to eq('ai_agent')
  end

  # Pega: desligar a Fase 2 (ou o agente virar interno) travar o save de qualquer outra coisa da Atribuição.
  it 'regra já salva com a Lia: salvar o resto continua funcionando sem a Fase 2' do
    salvar({ enabled: true, pool_type: 'ai_agent', pool_id: lia.id })
    Autonomia::Agents::Fase2.desligar!(account)

    salvar({ enabled: true, pool_type: 'ai_agent', pool_id: lia.id, prefer_online: false })

    expect(response).to have_http_status(:ok)
  end

  it 'sem a Fase 2: não aceita agente' do
    Autonomia::Agents::Fase2.desligar!(account)

    salvar({ enabled: true, pool_type: 'ai_agent', pool_id: lia.id })

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
