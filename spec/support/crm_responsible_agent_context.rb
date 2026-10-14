# Cenário do agente de IA responsável por caixa + funil (#1447): uma caixa com a porta (o agente que atende primeiro),
# a Área Suporte vinculada como área (Autonomia::Agents::Areas), dois funis (Comercial sem responsável, Suporte com a
# Área Suporte) e uma conversa atendida pela porta. A conta tem os Agentes e a Fase 2 ligados.
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
  let(:agente_da_porta) { criar_agente('Porta') }
  let(:vinculo_da_porta) do
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente_da_porta, inbox: inbox).perform(connect: true).agent_inbox
  end
  let(:porta) { vinculo_da_porta.agent_bot }
  let(:area) { criar_agente('Área Suporte') }
  # Areas.vincular! é idempotente: chamar de novo devolve o mesmo vínculo.
  let(:espelho_area) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox).agent_bot }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    [comercial, suporte].each do |pipeline|
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, created_by: admin)
    end
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true)
    vinculo_da_porta
    espelho_area
    Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: suporte, agent: area)
    conversation.update!(ai_assignee: porta)
  end

  def criar_agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  # O vínculo de área some por fora (sem callbacks): o agente segue ligado, mas não é mais área da caixa.
  def area_sumiu!(agente = area)
    Autonomia::Agents::AgentInbox.where(agent: agente).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
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
