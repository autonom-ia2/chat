require 'rails_helper'

# #1593 — ponta a ponta com o PassarParaIa REAL (PR-B dos Agentes IA, mescla local de teste) e o Crm::Passagens real.
# Só o Crm::Passagens.com_motivo (PR B da #1606) segue dublado, e só no caminho de pessoa.
RSpec.describe 'Agente de IA na Atribuição e no Passar para, ponta a ponta' do
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
    comercial.stages.first.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct',
                                                                  'pool_type' => 'ai_agent', 'pool_id' => area.id } })
  end

  # Pega: a conversa ficar com a área mas presa em "Não atribuídas" (marca de espera do robô ou do motor de entrega).
  it 'robô passa com "A mesma pessoa" na área: a área assume e a conversa sai de Não atribuídas', :aggregate_failures do
    regra_na_area!

    conversation.bot_handoff!

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

  # Pega: a área que pede pessoa recebendo de volta dela mesma (laço).
  it 'a própria área passa: ja_e_o_dono e vai para alguém da equipe', :aggregate_failures do
    regra_na_area!
    conversation.update!(ai_assignee: espelho_area)

    conversation.bot_handoff!

    expect(conversation.reload.assignee_id).to be_in([ana.id, bruno.id])
  end

  describe 'Passar para… na conversa' do
    before { dublar_com_motivo }

    it 'Ana passa para a área; o selo mostra a origem; Ana devolve para si', :aggregate_failures do
      conversation.update!(assignee: ana, ai_assignee: nil)
      servico = Crm::PassarPara.new(conversation: conversation, usuario: ana)

      expect(servico.passar!(tipo: 'ia', id: area.id).ok).to be(true)
      conversation.reload
      expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      retrato = Crm::PassarPara.new(conversation: conversation, usuario: ana).retrato
      expect(retrato[:com_ia]).to include(id: area.id)
      expect(retrato[:origem]).to include(tipo: 'pessoa', id: ana.id, pode_receber: true)

      expect(Crm::PassarPara.new(conversation: conversation, usuario: ana).passar!(tipo: 'pessoa', id: ana.id).ok).to be(true)
      expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    end

    it 'Bruno pede a passagem da conversa da Ana: pedida_por é o Bruno, origem a Ana' do
      conversation.update!(assignee: ana, ai_assignee: nil)

      Crm::PassarPara.new(conversation: conversation, usuario: bruno).passar!(tipo: 'ia', id: area.id)

      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect([passagem.de.id, passagem.pedida_por.id]).to eq([ana.id, bruno.id])
    end
  end
end
