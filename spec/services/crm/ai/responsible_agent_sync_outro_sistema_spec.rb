require 'rails_helper'

# #1648 — decisão do Rodrigo de 15/10: numa caixa com um agente de outro sistema (n8n) atendendo primeiro e uma área
# vinculada (opção B), quando o assunto do CRM cai num funil que tem essa área como responsável, a conversa PASSA para a
# área. É a mesma regra dos nossos agentes (Crm::Ai::ResponsibleAgentSync).
RSpec.describe Crm::Ai::ResponsibleAgentSync do
  include ActiveJob::TestHelper

  let(:account) { create(:account, internal_attributes: { 'autonomia_agente_ia_por_caixa' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:comercial) { create_crm_pipeline(account: account, user: admin, name: 'Comercial').first }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte').first }
  let(:outro_sistema) { create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook') }
  let(:area) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Área Suporte', agent_type: 'custom', status: :active, enabled: true)
  end
  let(:vinculo_da_area) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(pipeline: comercial, stage: comercial.stages.first, contact: contact,
                              primary_conversation: conversation, inbox: inbox, title: 'Pedido')
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    [comercial, suporte].each do |pipeline|
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, created_by: admin)
    end
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true)
    AgentBotInbox.create!(inbox: inbox, agent_bot: outro_sistema, account: account)
    vinculo_da_area
    Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: suporte, agent: area)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: Time.current)
    clear_enqueued_jobs
  end

  # O assunto em atendimento muda para o funil que tem a área como responsável; os jobs do CRM rodam.
  def mudar_o_assunto_para_suporte
    eventos = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { eventos << payload }, described_class::EVENTO_TROCA) do
      perform_enqueued_jobs { card.reload.update!(pipeline: suporte, stage: suporte.stages.first) }
    end
    eventos
  end

  it 'a conversa nasce com o agente de outro sistema, e a área é responsável pelo funil Suporte' do
    expect(conversation.reload.ai_assignee).to eq(outro_sistema)
    expect(Crm::Ai::Config.responsible_agent(inbox: inbox, pipeline: suporte)).to eq(area)
  end

  it 'passa a conversa do agente de outro sistema para a área, com um evento de troca' do
    eventos = mudar_o_assunto_para_suporte

    expect(conversation.reload).to have_attributes(ai_assignee: vinculo_da_area.agent_bot, assignee_id: nil)
    expect(eventos.size).to eq(1)
    expect(eventos.sole).to include(from_bot: outro_sistema, to_bot: vinculo_da_area.agent_bot, agent: area,
                                    motivo: described_class::PIPELINE)
  end

  # Na main de 15/10 o Sync troca o robô pelo AssignmentService e grava a atividade do card (ai_agent_changed), mas não
  # grava a passagem: o Crm::Passagens só registra troca de PESSOA (ConversationPassagem, assignee_id). Fazer o Sync
  # passar pela Autonomia::Agents::PassarParaIa (que grava a passagem) é o #1625, do Multifunnel. Quando ele entrar,
  # este exemplo passa e o RSpec avisa para tirar o `pending`.
  it 'ponta a ponta: a área vira a ai_assignee, com exatamente 1 passagem registrada e 1 evento' do
    pending 'a passagem do Sync robô → área no Crm::Passagens vem no #1625 (Sync pela PassarParaIa)'

    eventos = mudar_o_assunto_para_suporte

    expect(conversation.reload.ai_assignee).to eq(vinculo_da_area.agent_bot)
    expect(eventos.size).to eq(1)
    expect(Crm::Passagem.where(conversation_id: conversation.id).count).to eq(1)
  end
end
