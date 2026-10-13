require 'rails_helper'

# #1433 F1a — vínculo de ÁREA (agente da equipe): recebe a conversa quando alguém passa, com espelho próprio e SEM
# AgentBotInbox, para que inbox.agent_bot continue sendo a porta. Chamado pela tela do CRM "Quem cuida do quê?" (#1447).
RSpec.describe Autonomia::Agents::Areas do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  let(:agente_da_porta) { agente('Porta') }
  let(:agente_da_area) { agente('Financeiro') }
  let!(:porta) do
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente_da_porta, inbox: inbox).perform(connect: true).agent_inbox
  end

  def agente(nome, **attrs)
    Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  describe '.vincular!' do
    it 'cria o vínculo de área com espelho próprio, sem AgentBotInbox, e a caixa segue com a porta' do
      vinculo = described_class.vincular!(agent: agente_da_area, inbox: inbox)

      expect(vinculo).to have_attributes(papel: 'area', agent: agente_da_area, inbox: inbox, account: account)
      expect(vinculo.agent_bot).to have_attributes(outgoing_url: nil, name: 'Financeiro', account_id: account.id)
      expect(vinculo.agent_bot_id).not_to eq(porta.agent_bot_id)
      expect(AgentBotInbox.where(agent_bot_id: vinculo.agent_bot_id)).to be_empty
      expect(inbox.reload.agent_bot).to eq(porta.agent_bot)
    end

    it 'é idempotente: a segunda chamada devolve o mesmo vínculo, sem novo espelho' do
      primeiro = described_class.vincular!(agent: agente_da_area, inbox: inbox)

      expect { described_class.vincular!(agent: agente_da_area, inbox: inbox) }
        .not_to(change { [AgentBot.count, Autonomia::Agents::AgentInbox.count] })
      expect(described_class.vincular!(agent: agente_da_area, inbox: inbox)).to eq(primeiro)
    end

    it 'recusa caixa sem porta ativa, sem deixar espelho para trás' do
      outra_caixa = create(:inbox, account: account)

      expect { described_class.vincular!(agent: agente_da_area, inbox: outra_caixa) }
        .to raise_error(ActiveRecord::RecordInvalid)
        .and(not_change(AgentBot, :count))
    end

    it 'recusa o próprio agente da porta como área da mesma caixa' do
      expect { described_class.vincular!(agent: agente_da_porta, inbox: inbox) }
        .to raise_error(ActiveRecord::RecordInvalid)
        .and(not_change(AgentBot, :count))
    end

    it 'recusa agente interno (copiloto da equipe nunca fala com cliente)' do
      interno = agente('Copiloto', actuation: :internal)

      expect { described_class.vincular!(agent: interno, inbox: inbox) }
        .to raise_error(described_class::AgenteInterno)
    end

    it 'recusa caixa de outra conta' do
      caixa_alheia = create(:inbox, account: create(:account))

      expect { described_class.vincular!(agent: agente_da_area, inbox: caixa_alheia) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '.desvincular!' do
    let!(:area) { described_class.vincular!(agent: agente_da_area, inbox: inbox) }

    def conversa(**attrs)
      create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(attrs) }
    end

    it 'solta o vínculo (guardando o espelho, autor das mensagens antigas) e devolve à porta as conversas da área' do
      atendida = conversa(ai_assignee: area.agent_bot, status: :open)
      da_porta = conversa(ai_assignee: porta.agent_bot, status: :open)
      resposta_antiga = create(:message, account: account, conversation: atendida, message_type: :outgoing, sender: area.agent_bot)

      described_class.desvincular!(agent: agente_da_area, inbox: inbox)

      expect(Autonomia::Agents::AgentInbox.kept.area).to be_empty
      expect(area.reload.deleted_at).to be_present
      expect(resposta_antiga.reload.sender).to eq(area.agent_bot)
      expect(atendida.reload).to have_attributes(assignee_agent_bot_id: porta.agent_bot_id, status: 'open')
      expect(da_porta.reload.assignee_agent_bot_id).to eq(porta.agent_bot_id)
      expect(porta.reload.deleted_at).to be_nil
    end

    it 'conversa que esperava pessoa segue para a equipe humana, sem robô' do
      esperando = conversa(ai_assignee: area.agent_bot, status: :open)
      esperando.bot_handoff!

      described_class.desvincular!(agent: agente_da_area, inbox: inbox)

      expect(esperando.reload).to have_attributes(assignee_agent_bot_id: nil, status: 'open')
    end

    it 'com a porta desligada, a conversa da área vai para a equipe humana' do
      atendida = conversa(ai_assignee: area.agent_bot, status: :open)
      agente_da_porta.update!(enabled: false)

      described_class.desvincular!(agent: agente_da_area, inbox: inbox)

      expect(atendida.reload.assignee_agent_bot_id).to be_nil
    end

    it 'vincular de novo reativa o mesmo vínculo e o mesmo espelho' do
      described_class.desvincular!(agent: agente_da_area, inbox: inbox)

      expect { described_class.vincular!(agent: agente_da_area, inbox: inbox) }.not_to change(AgentBot, :count)
      expect(area.reload).to have_attributes(deleted_at: nil, papel: 'area')
    end

    it 'é idempotente e não toca a porta' do
      described_class.desvincular!(agent: agente_da_area, inbox: inbox)

      expect { described_class.desvincular!(agent: agente_da_area, inbox: inbox) }.not_to raise_error
      expect { described_class.desvincular!(agent: agente_da_porta, inbox: inbox) }
        .not_to(change { porta.reload.attributes })
    end
  end
end
