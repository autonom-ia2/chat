require 'rails_helper'

# #1593 — ponta a ponta n8n → Atribuição → área. O robô de outro sistema (n8n) passa a conversa como sempre passou
# (toggle_status open, com o token dele) e quem decide para onde ela vai é a regra da Atribuição do funil: com
# "A mesma pessoa" num agente de IA, a área assume. Nenhum agente nosso dispara passagem (#2154). Tudo real, pelo HTTP.
# Cada cenário diz que falha pega.
RSpec.describe 'n8n passa a conversa pela Atribuição', type: :request do
  include_context 'with crm responsible agent'

  let(:caixa_n8n) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:n8n) { create(:agent_bot, account: account, name: 'Robô n8n') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa_n8n, contact: contact, status: :open).reload }
  let(:espelho) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: caixa_n8n).agent_bot }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:etapa) { comercial.stages.first }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    Autonomia::Agents::AgenteIaPorCaixa.ligar!(account)
    create(:agent_bot_inbox, inbox: caixa_n8n, agent_bot: n8n)
    create(:inbox_member, inbox: caixa_n8n, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    account.crm_pipeline_inboxes.create!(pipeline: comercial, inbox: caixa_n8n, default_stage: etapa, created_by: admin)
    account.crm_inbox_settings.create!(inbox: caixa_n8n, crm_enabled: true)
    espelho
    conversa.update!(assignee: nil, ai_assignee: n8n)
    card_na_conversa!
  end

  def card_na_conversa!
    card = account.crm_cards.create!(pipeline: comercial, stage: etapa, contact: contact, primary_conversation: conversa,
                                     inbox: caixa_n8n, title: 'Pedido')
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa)
                         .update!(is_primary: true, focused_at: Time.current)
  end

  def regra!(pool)
    etapa.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' }.merge(pool) })
  end

  def regra_na_area!
    regra!('pool_type' => 'ai_agent', 'pool_id' => area.id)
  end

  def n8n_passa!
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/toggle_status",
         params: { status: 'open' }, headers: { api_access_token: n8n.access_token.token }, as: :json
  end

  # Pega: o pedido do n8n ignorar a regra da etapa e cair numa pessoa (ou ficar parado em "Não atribuídas").
  it '"A mesma pessoa" na área: a área assume, sem pessoa e sem espera, e a passagem sai do agente externo',
     :aggregate_failures do
    regra_na_area!

    expect { n8n_passa! }.to change(Crm::Passagem, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(conversa.reload).to have_attributes(ai_assignee: espelho, assignee_id: nil, status: 'open')
    expect(Conversation.awaiting_person.where(id: conversa.id)).to be_empty
    expect(Crm::Entrega::Marca.presente?(conversa)).to be(false)
    passagem = Crm::Passagens.ultima_aberta(conversa)
    expect([passagem.de.classe, passagem.de.id]).to eq(['AgentBot', n8n.id])
    expect([passagem.para.classe, passagem.para.id]).to eq(['Autonomia::Agents::Agent', area.id])
  end

  # Pega: o n8n continuar respondendo depois de passar. O filtro dele (FiltraSomenteNaoAtribuido) só cala quando o
  # dono é outro robô; e a área precisa saber de quem recebeu ("agente externo").
  it 'depois da passagem o n8n vê outro dono e a área sabe que veio do agente externo', :aggregate_failures do
    regra_na_area!

    n8n_passa!

    meta = conversa.reload.push_event_data[:meta]
    expect(meta[:assignee_type]).to eq('AgentBot')
    expect(meta.dig(:assignee, :name)).not_to eq(n8n.name)
    expect(Crm::Passagens.recentes(conversa)).to include('agente externo').and include('Robô n8n')
    expect(Autonomia::Agents::QuemResponde.agent_inbox(conversa)&.agent).to eq(area)
  end

  # Pega: a regra de IA vazar para quem configurou a equipe. É o mesmo pedido; quem muda o destino é só a regra.
  it 'regra na equipe: o mesmo pedido vai para a pessoa', :aggregate_failures do
    regra!('pool_type' => 'inbox')

    n8n_passa!

    expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
  end

  # Pega: agente parado recebendo conversa porque a regra ainda aponta para ele.
  it 'área parada: fora dos destinos, a pessoa da equipe recebe', :aggregate_failures do
    regra_na_area!
    area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

    n8n_passa!

    expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
  end

  # Pega: o pedido do robô tirar a conversa da pessoa que está atendendo (pessoa no nome vence).
  it 'pessoa no nome: a conversa fica com ela, sem passagem', :aggregate_failures do
    regra_na_area!
    conversa.update!(assignee: ana)

    expect { n8n_passa! }.not_to change(Crm::Passagem, :count)

    expect(conversa.reload).to have_attributes(assignee_id: ana.id)
    expect(conversa.ai_assignee).not_to eq(espelho)
  end

  # Pega (limite conhecido): a regra é do funil. Conversa sem card não tem regra e vai só para pessoas.
  it 'conversa sem card no funil: sem regra, vai para a pessoa', :aggregate_failures do
    regra_na_area!
    Crm::CardConversation.where(conversation: conversa).delete_all
    account.crm_cards.where(primary_conversation: conversa).delete_all

    n8n_passa!

    expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
  end
end
