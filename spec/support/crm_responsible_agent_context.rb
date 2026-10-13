# Cenário do agente de IA responsável por caixa + funil (#1447): uma caixa com a porta (robô ativo da caixa), dois funis
# (Comercial sem responsável, Suporte com a Área Suporte) e uma conversa atendida pela porta.
#
# Até a F1 do Agentes IA (#1433) uma caixa tem um só vínculo de agente nativo (AgentInbox); por isso a porta aqui é um
# robô comum da caixa e a área é o agente nativo ligado a ela, com o próprio espelho.
RSpec.shared_context 'with crm responsible agent' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload }
  let(:comercial_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
  let(:comercial) { comercial_and_stage.first }
  let(:suporte_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Suporte') }
  let(:suporte) { suporte_and_stage.first }
  let(:porta) { create(:agent_bot, account: account, name: 'Porta') }
  let(:area) { Autonomia::Agents::Agent.create!(account: account, name: 'Área Suporte', agent_type: 'custom') }
  let(:espelho_area) { create(:agent_bot, account: account, name: 'Área Suporte', outgoing_url: nil) }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    [comercial, suporte].each do |pipeline|
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, created_by: admin)
    end
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: porta, status: 'active')
    Autonomia::Agents::AgentInbox.create!(account: account, inbox: inbox, agent: area, agent_bot: espelho_area)
    Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: suporte, agent: area)
    conversation.update!(ai_assignee: porta)
  end

  def create_card(pipeline:, title: 'Pedido', focused_at: Time.current)
    card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, contact: contact,
                                     primary_conversation: conversation, inbox: inbox, title: title)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: focused_at)
    card
  end

  def esperar_pessoa!
    conversation.update!(additional_attributes: { Conversation::BOT_HANDOFF_WAITING_SINCE_KEY => Time.current.iso8601 })
  end
end
