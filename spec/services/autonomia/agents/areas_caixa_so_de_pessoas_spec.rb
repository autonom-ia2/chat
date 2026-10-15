require 'rails_helper'

# #1433 (tema 13) — agente da equipe (área) em caixa atendida só por pessoas: sem principal (porta) e sem robô de fora.
# Decisão do Rodrigo de 15/10 (#1593): sem isso o cenário humano → IA → humano não funciona. Ali a área só responde
# quando é DONA da conversa (o espelho dela é o ai_assignee, por passagem); conversa nova nasce sem robô e ninguém
# responde. Caixa com agente de outro sistema também aceita (#1648, decisão do Rodrigo de 15/10, opção B).
RSpec.describe Autonomia::Agents::Areas do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Vendas') }
  let(:da_equipe) { agente('Financeiro') }

  def agente(nome, conta: account)
    Autonomia::Agents::Agent.create!(account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end

  def agente_de_outro_sistema(caixa)
    AgentBotInbox.create!(inbox: caixa, agent_bot: create(:agent_bot, account: caixa.account), account: caixa.account)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  describe '.vincular! em caixa sem principal' do
    it 'aceita a caixa só de pessoas: vínculo de área, espelho sem AgentBotInbox, e a caixa segue sem robô' do
      vinculo = described_class.vincular!(agent: da_equipe, inbox: inbox)

      expect(vinculo).to have_attributes(papel: 'area', inbox: inbox, deleted_at: nil)
      expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
      expect(inbox.reload.agent_bot).to be_nil
      expect(da_equipe.reload.tem_onde_trabalhar?).to be(true)
    end

    it 'aceita mais de uma área na mesma caixa só de pessoas' do
      described_class.vincular!(agent: da_equipe, inbox: inbox)

      expect(described_class.vincular!(agent: agente('Suporte'), inbox: inbox)).to have_attributes(papel: 'area')
    end

    it 'aceita a caixa com agente de outro sistema: a área entra e ele continua sendo o robô da caixa (#1648)' do
      bot_inbox = agente_de_outro_sistema(inbox)

      vinculo = described_class.vincular!(agent: da_equipe, inbox: inbox)

      expect(vinculo).to have_attributes(papel: 'area', deleted_at: nil)
      expect(AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)).to eq([bot_inbox.agent_bot_id])
    end

    it 'caixa com principal parado continua recusada' do
      principal = agente('Porta')
      Autonomia::Agents::Operate::InboxConnector.new(agent: principal, inbox: inbox).perform(connect: true)
      principal.update_columns(status: Autonomia::Agents::Agent.statuses[:paused], enabled: false) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.vincular!(agent: da_equipe, inbox: inbox) }
        .to raise_error(described_class::CaixaNaoAceitaArea) { |erro| expect(erro.codigo).to eq(:principal_parado) }
        .and(not_change(Autonomia::Agents::AgentInbox, :count))
    end

    it 'isola a conta: caixa só de pessoas de outra conta é recusada' do
      caixa_de_fora = create(:inbox, account: create(:account))

      expect { described_class.vincular!(agent: da_equipe, inbox: caixa_de_fora) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Autonomia::Agents::AgentInbox.where(inbox: caixa_de_fora)).to be_empty
    end
  end

  describe 'quem responde na caixa só de pessoas' do
    let!(:area) { described_class.vincular!(agent: da_equipe, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }

    before { Autonomia::Agents::Fase2.ligar!(account) }

    def responde_com(texto)
      answer = Autonomia::Agents::AnswerResult.new(
        reply: texto, confidence: 0.9, handoff: { should: false, reason: nil }, used_knowledge: [], answered_from_knowledge: false
      )
      allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
    end

    def turno(texto)
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto)
      Autonomia::Agents::Operate::ReplyJob.perform_now(conversation.id, message.id, 'trigger')
      Autonomia::Agents::Operate::ReplyJob.perform_now(conversation.id, message.id, 'settle')
    end

    def respostas_do_robo
      conversation.messages.outgoing.where(sender_type: 'AgentBot', private: false)
    end

    it 'conversa nova nasce sem robô e ninguém responde: a área nunca abre conversa sozinha' do
      expect(Autonomia::Agents::Answerer).not_to receive(:new)

      expect(conversation).to have_attributes(assignee_agent_bot_id: nil, status: 'open')
      expect(Autonomia::Agents::QuemResponde.agent_inbox(conversation)).to be_nil
      expect(Autonomia::Agents::Operate.eligible_agent_inbox(conversation)).to be_nil

      turno('oi, quero o boleto')

      expect(respostas_do_robo).to be_empty
    end

    it 'com a área dona da conversa (passagem), ela responde com o próprio espelho e continua dona' do
      conversation.update!(ai_assignee: area.agent_bot)
      responde_com('Aqui é o financeiro.')

      expect(Autonomia::Agents::Operate.eligible_agent_inbox(conversation)).to eq(area)

      turno('quero o boleto')

      expect(respostas_do_robo.count).to eq(1)
      expect(respostas_do_robo.first).to have_attributes(sender_id: area.agent_bot_id, content: 'Aqui é o financeiro.')
      expect(conversation.reload.assignee_agent_bot_id).to eq(area.agent_bot_id)
    end

    it 'pessoa atribuída cala a área, mesmo dona' do
      conversation.update!(ai_assignee: area.agent_bot, assignee: create(:user, account: account, role: :agent))
      expect(Autonomia::Agents::Answerer).not_to receive(:new)

      turno('oi')

      expect(respostas_do_robo).to be_empty
    end

    it 'área dona parada: ninguém responde no lugar dela (não há principal para assumir)' do
      conversation.update!(ai_assignee: area.agent_bot)
      da_equipe.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

      expect(Autonomia::Agents::QuemResponde.agent_inbox(conversation)).to be_nil
    end

    it 'sem a Fase 2 na conta, ninguém responde, mesmo com a área dona' do
      Autonomia::Agents::Fase2.desligar!(account)
      conversation.update!(ai_assignee: area.agent_bot)

      expect(Autonomia::Agents::Operate.eligible_agent_inbox(conversation.reload)).to be_nil
    end

    it 'isola a conta: o espelho da área não responde por conversa de outra conta' do
      outra = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      Autonomia::Agents::Fase2.ligar!(outra)
      alheia = create(:conversation, account: outra, inbox: create(:inbox, account: outra), assignee: nil)
      alheia.update_columns(assignee_agent_bot_id: area.agent_bot_id, ai_assignee_type: 'AgentBot') # rubocop:disable Rails/SkipsModelValidations

      expect(Autonomia::Agents::QuemResponde.agent_inbox(alheia)).to be_nil
      expect(Autonomia::Agents::Operate.authorized_agent_inbox(alheia)).to be_nil
    end
  end

  describe 'saída da caixa só de pessoas' do
    let!(:area) { described_class.vincular!(agent: da_equipe, inbox: inbox) }
    let!(:outra_area) { described_class.vincular!(agent: agente('Suporte'), inbox: inbox) }

    it 'soltar a área devolve as conversas dela às pessoas (sem robô) e não toca a outra área' do
      da_area = create(:conversation, account: account, inbox: inbox, status: :open, assignee_agent_bot_id: area.agent_bot_id)

      described_class.desvincular!(agent: da_equipe, inbox: inbox)

      expect(da_area.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(outra_area.reload.deleted_at).to be_nil
    end

    it 'apagar o agente de uma área não solta as outras áreas da caixa' do
      Autonomia::Agents::SoftDelete.new(agent: da_equipe, actor: nil).perform

      expect(area.reload.deleted_at).to be_present
      expect(outra_area.reload.deleted_at).to be_nil
      expect(outra_area.agent.reload).to be_operating
    end

    it 'o principal que sai de outra caixa não toca as áreas desta' do
      outra_caixa = create(:inbox, account: account)
      principal = agente('Porta')
      Autonomia::Agents::Operate::InboxConnector.new(agent: principal, inbox: outra_caixa).perform(connect: true)

      Autonomia::Agents::Operate::InboxConnector.new(agent: principal, inbox: outra_caixa).perform(connect: false)

      expect(Autonomia::Agents::AgentInbox.kept.area.where(inbox_id: inbox.id)).to contain_exactly(area, outra_area)
    end
  end
end
