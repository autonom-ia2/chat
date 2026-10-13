require 'rails_helper'

# #1433 F1a — o ponto único que escolhe o vínculo (agente) que responde por uma conversa.
# Chave da Fase 2 desligada: sempre a porta da caixa, como hoje. Ligada: o dono da conversa (ai_assignee que é espelho
# de um vínculo ativo da caixa), senão a porta.
RSpec.describe Autonomia::Agents::QuemResponde do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def agente(nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true)
  end

  def porta_em(caixa, nome = 'Porta')
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente(nome), inbox: caixa).perform(connect: true).agent_inbox
  end

  # A consulta de antes do #1433, copiada dos ~14 pontos que escolhiam o agente pela caixa.
  def consulta_de_antes(conversa)
    Autonomia::Agents::AgentInbox.kept.find_by(inbox_id: conversa.inbox_id, account_id: conversa.account_id)
  end

  describe 'chave da Fase 2 desligada (equivalência com hoje)' do
    it 'devolve o mesmo vínculo da consulta de antes, com e sem robô atribuído' do
      porta = porta_em(inbox)
      sem_dono = create(:conversation, account: account, inbox: inbox)
      com_dono = create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(ai_assignee: porta.agent_bot) }

      [sem_dono, com_dono].each do |conversa|
        expect(described_class.agent_inbox(conversa)).to eq(consulta_de_antes(conversa))
      end
      expect(described_class.agent_inbox(sem_dono)).to eq(porta)
    end

    it 'devolve nil como antes quando a caixa não tem agente, ou o vínculo foi apagado' do
      expect(described_class.agent_inbox(conversation)).to be_nil
      expect(consulta_de_antes(conversation)).to be_nil

      porta_em(inbox).update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.agent_inbox(conversation)).to be_nil
      expect(consulta_de_antes(conversation)).to be_nil
    end

    it 'não lê vínculo de outra conta' do
      outra = create(:account)
      agente_alheio = Autonomia::Agents::Agent.create!(account: outra, name: 'X', agent_type: 'custom')
      Autonomia::Agents::AgentInbox.new(account: outra, inbox: inbox, agent: agente_alheio,
                                        agent_bot: AgentBot.create!(account: outra, name: 'E')).save!(validate: false)

      expect(described_class.agent_inbox(conversation)).to be_nil
    end

    it 'responde a porta mesmo quando a conversa está com o espelho de uma área' do
      porta = porta_em(inbox)
      area = Autonomia::Agents::Areas.vincular!(agent: agente('Área'), inbox: inbox)
      conversation.update!(ai_assignee: area.agent_bot)

      expect(described_class.agent_inbox(conversation)).to eq(porta)
    end

    it 'nil para conversa vazia' do
      expect(described_class.agent_inbox(nil)).to be_nil
    end
  end

  describe 'chave da Fase 2 ligada' do
    before { Autonomia::Agents::Fase2.ligar!(account) }

    let!(:porta) { porta_em(inbox) }
    let!(:area) { Autonomia::Agents::Areas.vincular!(agent: agente('Financeiro'), inbox: inbox) }

    it 'quem responde é a área quando o espelho dela é o ai_assignee' do
      conversation.update!(ai_assignee: area.agent_bot)

      expect(described_class.agent_inbox(conversation)).to eq(area)
    end

    it 'quem responde é a porta quando o ai_assignee é o espelho da porta, ou não há ai_assignee' do
      expect(described_class.agent_inbox(conversation)).to eq(porta)

      conversation.update!(ai_assignee: porta.agent_bot)
      expect(described_class.agent_inbox(conversation)).to eq(porta)
    end

    it 'cai na porta quando o ai_assignee é um robô que não é espelho de vínculo ativo desta caixa' do
      outra_caixa = create(:inbox, account: account)
      porta_em(outra_caixa, 'Outra porta')
      area_de_outra_caixa = Autonomia::Agents::Areas.vincular!(agent: agente('Outra área'), inbox: outra_caixa)

      conversation.update!(ai_assignee: area_de_outra_caixa.agent_bot)
      expect(described_class.agent_inbox(conversation)).to eq(porta)

      conversation.update!(ai_assignee: AgentBot.create!(account: account, name: 'Qualquer'))
      expect(described_class.agent_inbox(conversation)).to eq(porta)
    end

    it 'cai na porta quando o vínculo da área foi apagado' do
      conversation.update!(ai_assignee: area.agent_bot)
      area.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.agent_inbox(conversation)).to eq(porta)
    end
  end

  describe '.porta_da_caixa' do
    it 'devolve só a porta ativa da caixa' do
      porta = porta_em(inbox)
      Autonomia::Agents::Areas.vincular!(agent: agente('Área'), inbox: inbox)

      expect(described_class.porta_da_caixa(inbox)).to eq(porta)
      expect(described_class.porta_da_caixa(create(:inbox, account: account))).to be_nil
    end
  end
end
