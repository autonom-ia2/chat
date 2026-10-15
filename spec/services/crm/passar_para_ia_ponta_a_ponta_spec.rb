require 'rails_helper'

# #1593 — ponta a ponta: a passagem do robô (bot_handoff!), a Atribuição, o serviço dos Agentes (PassarParaIa, #1628) e
# o registro de passagens (Crm::Passagens, com o com_motivo e o listener do #1622), todos reais. Nada dublado.
RSpec.describe 'Agente de IA na Atribuição e no Passar para, ponta a ponta' do # rubocop:disable RSpec/DescribeClass
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Lima') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    [ana, bruno].each { |pessoa| create(:inbox_member, inbox: inbox, user: pessoa) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online', bruno.id.to_s => 'online' })
    create_card(pipeline: comercial)
  end

  def regra_na_area!
    regra = { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'pool_type' => 'ai_agent', 'pool_id' => area.id }
    comercial.stages.first.update!(metadata: { 'ai_handoff' => regra })
  end

  # Pega: a conversa ficar com a área mas presa em "Não atribuídas" (marca de espera do robô ou do motor de entrega).
  it 'robô passa com "A mesma pessoa" na área: a área assume e a conversa sai de Não atribuídas', :aggregate_failures do
    regra_na_area!

    expect { conversation.bot_handoff! }.to change(Crm::Passagem, :count).by(1)

    conversation.reload
    expect(conversation).to have_attributes(ai_assignee: espelho_area, assignee_id: nil, status: 'open')
    expect(conversation.additional_attributes.to_h[Conversation::BOT_HANDOFF_WAITING_SINCE_KEY]).to be_nil
    expect(Crm::Entrega::Marca.presente?(conversation)).to be(false)
    expect(Conversation.awaiting_person.where(id: conversation.id)).to be_empty
    passagem = Crm::Passagens.ultima_aberta(conversation)
    expect([passagem.de.classe, passagem.de.id]).to eq(['Autonomia::Agents::Agent', agente_da_porta.id])
    expect([passagem.para.classe, passagem.para.id]).to eq(['Autonomia::Agents::Agent', area.id])
  end

  it 'área parada: o serviço recusa e alguém da equipe recebe', :aggregate_failures do
    regra_na_area!
    area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

    conversation.bot_handoff!

    expect(conversation.reload.assignee_id).to be_in([ana.id, bruno.id])
    expect(conversation.ai_assignee).to be_nil
  end

  # Pega: o laço. A área passa por bot_handoff! e "A mesma pessoa" = a própria área. Com o PR-B #1628 o serviço dos
  # Agentes responde `passou` para quem espera pessoa; quem barra é o CRM, antes de chamá-lo.
  it 'a própria área passa: vai para alguém da equipe, sem voltar para ela, com uma passagem só', :aggregate_failures do
    regra_na_area!
    conversation.update!(ai_assignee: espelho_area)
    Crm::Passagem.where(conversation_id: conversation.id).delete_all
    allow(Autonomia::Agents::PassarParaIa).to receive(:call).and_call_original

    expect { conversation.bot_handoff! }.to change(Crm::Passagem, :count).by(1)

    conversation.reload
    expect(conversation.assignee_id).to be_in([ana.id, bruno.id])
    expect(conversation.ai_assignee).not_to eq(espelho_area)
    expect(Autonomia::Agents::PassarParaIa).not_to have_received(:call)
    passagem = Crm::Passagens.ultima_aberta(conversation)
    expect([passagem.de.classe, passagem.de.id]).to eq(['Autonomia::Agents::Agent', area.id])
    expect([passagem.para.classe, passagem.para.id]).to eq(['User', conversation.assignee_id])
  end

  # Pega: o laço pela fila. Ninguém online: a área segue esperando pessoa (marca do robô e do motor). Quando a Ana fica
  # online, a fila entrega a ela, não devolve à área (o caminho em que o #1628 deixou de responder ja_e_o_dono).
  it 'a área passa sem ninguém online e a fila entrega depois: vai para a Ana, nunca de volta à área', :aggregate_failures do
    regra_na_area!
    conversation.update!(ai_assignee: espelho_area)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    conversation.bot_handoff!
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
    expect(conversation.bot_handoff_waiting? || conversation.crm_delivery_pending?).to be(true)

    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    allow(Autonomia::Agents::PassarParaIa).to receive(:call).and_call_original
    Crm::Entrega.new(conversation: conversation, motivo: 'robo_pediu', origem: 'fila').call

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(Autonomia::Agents::PassarParaIa).not_to have_received(:call)
  end

  describe 'Passar para… na conversa' do
    it 'Ana passa para a área e a devolve: uma passagem por troca, selo com a origem, motivo passar_para', :aggregate_failures do
      conversation.update!(assignee: ana, ai_assignee: nil)
      Crm::Passagem.where(conversation_id: conversation.id).delete_all
      servico = Crm::PassarPara.new(conversation: conversation, usuario: ana)

      expect { expect(servico.passar!(tipo: 'ia', id: area.id).ok).to be(true) }.to change(Crm::Passagem, :count).by(1)
      conversation.reload
      expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      retrato = Crm::PassarPara.new(conversation: conversation, usuario: ana).retrato
      expect(retrato[:com_ia]).to include(id: area.id)
      expect(retrato[:origem]).to include(tipo: 'pessoa', id: ana.id, pode_receber: true)

      Current.user = ana
      expect do
        expect(Crm::PassarPara.new(conversation: conversation, usuario: ana).passar!(tipo: 'pessoa', id: ana.id).ok).to be(true)
      end.to change(Crm::Passagem, :count).by(1)
      expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
      ultima = Crm::Passagem.where(conversation_id: conversation.id).em_ordem.first
      expect(ultima.motivo).to eq('passar_para')
      expect([ultima.para.classe, ultima.para.id]).to eq(['User', ana.id])
      expect(Crm::Passagem.where(conversation_id: conversation.id).abertas.count).to eq(1)
    ensure
      Current.reset
    end

    it 'Bruno pede a passagem da conversa da Ana: pedida_por é o Bruno, origem a Ana' do
      conversation.update!(assignee: ana, ai_assignee: nil)

      Crm::PassarPara.new(conversation: conversation, usuario: bruno).passar!(tipo: 'ia', id: area.id)

      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect([passagem.de.id, passagem.pedida_por.id]).to eq([ana.id, bruno.id])
    end
  end
end
