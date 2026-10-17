require 'rails_helper'

# #1366 — o agente não fica atendendo (active + enabled) sem ter onde trabalhar. Predicado único:
# Agent#tem_onde_trabalhar?. Saiu o último vínculo, o agente para (AgentInbox, um lugar só).
RSpec.describe Autonomia::Agents::Agent do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def agente(nome, **attrs)
    described_class.create!({ account: account, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  def conectar(agent, caixa)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true).agent_inbox
  end

  def desconectar(agent, caixa)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: false)
  end

  describe '#tem_onde_trabalhar?' do
    it 'é verdadeiro para o interno (Copiloto da equipe), sem caixa' do
      expect(agente('Ana', actuation: :internal).tem_onde_trabalhar?).to be(true)
    end

    it 'é verdadeiro para quem atende primeiro numa caixa (porta)' do
      porta = agente('Porta')
      conectar(porta, inbox)

      expect(porta.tem_onde_trabalhar?).to be(true)
    end

    it 'é verdadeiro para o agente da equipe numa caixa (área)' do
      conectar(agente('Porta'), inbox)
      area = agente('Financeiro')
      Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)

      expect(area.tem_onde_trabalhar?).to be(true)
    end

    it 'é falso sem nada, inclusive para o both (segue a regra do externo)' do
      expect(agente('Solto').tem_onde_trabalhar?).to be(false)
      expect(agente('Ambos', actuation: :both).tem_onde_trabalhar?).to be(false)
    end

    it 'é falso quando o único vínculo está apagado (deleted_at)' do
      porta = agente('Porta')
      vinculo = conectar(porta, inbox)
      vinculo.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(porta.reload.tem_onde_trabalhar?).to be(false)
    end

    it 'não conta vínculo de outra conta (isolamento)' do
      porta = agente('Porta')
      vinculo = conectar(porta, inbox)
      vinculo.update_columns(account_id: create(:account).id) # rubocop:disable Rails/SkipsModelValidations

      expect(porta.reload.tem_onde_trabalhar?).to be(false)
      expect(described_class.includes(:agent_inboxes).find(porta.id).tem_onde_trabalhar?).to be(false)
    end

    it 'dá a mesma resposta com os vínculos pré-carregados (a lista do index)' do
      com_caixa = agente('Porta')
      conectar(com_caixa, inbox)
      sem_caixa = agente('Solto')

      carregados = described_class.includes(:agent_inboxes).where(id: [com_caixa.id, sem_caixa.id]).index_by(&:id)

      expect(carregados[com_caixa.id].tem_onde_trabalhar?).to be(true)
      expect(carregados[sem_caixa.id].tem_onde_trabalhar?).to be(false)
    end
  end

  describe 'ativar sem onde trabalhar' do
    it 'recusa o externo parado e sem caixa, com a mensagem da regra' do
      parado = agente('Solto', status: :paused, enabled: false)

      expect(parado.update(status: :active, enabled: true)).to be(false)
      expect(parado.errors[:base]).to include(I18n.t('autonomia.agents.sem_onde_trabalhar'))
    end

    it 'recusa tirar o interno sem caixa do painel e deixá-lo atendendo como externo' do
      interno = agente('Ana', actuation: :internal)

      expect(interno.update(actuation: :external)).to be(false)
    end

    it 'aceita o interno, sem caixa' do
      interno = agente('Ana', actuation: :internal, status: :draft, enabled: false)

      expect(interno.update(status: :active, enabled: true)).to be(true)
    end

    it 'não barra editar outra coisa de quem já estava atendendo sem caixa (o caso antigo)' do
      antigo = agente('Livia')

      expect(antigo.update(name: 'Lívia')).to be(true)
    end
  end

  describe 'parada automática ao sair o último vínculo' do
    it 'para o agente ao desconectar a última caixa' do
      porta = agente('Porta')
      conectar(porta, inbox)

      expect(desconectar(porta, inbox)).to be_success
      expect(porta.reload).to have_attributes(status: 'paused', enabled: false)
    end

    it 'não para quando ainda sobra outra caixa' do
      porta = agente('Porta')
      outra = create(:inbox, account: account)
      conectar(porta, inbox)
      conectar(porta, outra)

      desconectar(porta, inbox)

      expect(porta.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'para o agente da equipe ao desvincular a última área' do
      conectar(agente('Porta'), inbox)
      area = agente('Financeiro')
      Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)

      Autonomia::Agents::Areas.desvincular!(agent: area, inbox: inbox)

      expect(area.reload).to have_attributes(status: 'paused', enabled: false)
    end

    # #1433 (decisão do Rodrigo de 15/10): a porta sai, a área fica (a caixa vira só de pessoas) e segue trabalhando.
    it 'para a porta que saiu, e a área da caixa continua com onde trabalhar' do
      porta = agente('Porta')
      conectar(porta, inbox)
      area = agente('Financeiro')
      Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)

      desconectar(porta, inbox)

      expect(porta.reload).to have_attributes(status: 'paused', enabled: false)
      expect(area.reload).to have_attributes(status: 'active', enabled: true)
      expect(area.tem_onde_trabalhar?).to be(true)
    end

    it 'não para a área que ainda é porta em outra caixa' do
      conectar(agente('Porta'), inbox)
      area = agente('Financeiro')
      conectar(area, create(:inbox, account: account))
      Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)

      Autonomia::Agents::Areas.desvincular!(agent: area, inbox: inbox)

      expect(area.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'para o agente quando a caixa é apagada' do
      porta = agente('Porta')
      conectar(porta, inbox)

      inbox.destroy!

      expect(porta.reload).to have_attributes(status: 'paused', enabled: false)
    end

    it 'não toca o agente de outra conta' do
      outra_conta = create(:account)
      vizinho = described_class.create!(account: outra_conta, name: 'Vizinho', agent_type: 'custom', status: :active, enabled: true)
      conectar(vizinho, create(:inbox, account: outra_conta))
      porta = agente('Porta')
      conectar(porta, inbox)

      desconectar(porta, inbox)

      expect(vizinho.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'o destroy do próprio agente não tenta pará-lo' do
      porta = agente('Porta')
      conectar(porta, inbox)

      expect { porta.destroy! }.not_to raise_error
      expect(described_class.exists?(porta.id)).to be(false)
    end
  end

  describe 'parada automática: soft delete, espelho e evento' do
    it 'o soft delete da porta não para a área que só tinha aquela caixa (#1433: a área fica)' do
      porta = agente('Porta')
      conectar(porta, inbox)
      area = agente('Financeiro')
      Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)

      Autonomia::Agents::SoftDelete.new(agent: porta, actor: nil).perform

      expect(area.reload).to have_attributes(status: 'active', enabled: true)
      expect(area.tem_onde_trabalhar?).to be(true)
    end

    it 'deixa espelho e bots coerentes depois de parar a porta' do
      porta = agente('Porta')
      vinculo = conectar(porta, inbox)
      espelho_id = vinculo.agent_bot_id

      desconectar(porta, inbox)

      expect(porta.reload.operating?).to be(false)
      expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
      expect(AgentBot.exists?(espelho_id)).to be(false)
      expect(inbox.reload.agent_bot).to be_nil
    end

    it 'deixa o espelho da área sem caixa ativa e guarda o autor das mensagens' do
      conectar(agente('Porta'), inbox)
      area = agente('Financeiro')
      vinculo = Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)

      Autonomia::Agents::Areas.desvincular!(agent: area, inbox: inbox)

      expect(area.reload.operating?).to be(false)
      expect(AgentBot.exists?(vinculo.agent_bot_id)).to be(true)
      expect(AgentBotInbox.where(agent_bot_id: vinculo.agent_bot_id)).to be_empty
    end

    it 'grava o evento da parada só com metadados, uma vez' do
      porta = agente('Porta')
      vinculo = conectar(porta, inbox)

      desconectar(porta, inbox)

      evento = porta.events.parado_sem_onde_trabalhar.sole
      expect(evento).to have_attributes(account_id: account.id, conversation_id: nil, message_id: nil)
      expect(evento.metadata).to eq('motivo' => 'sem_onde_trabalhar', 'vinculo_id' => vinculo.id,
                                    'inbox_id' => inbox.id, 'papel' => 'porta')
    end

    it 'não grava evento quando ainda sobra outra caixa' do
      porta = agente('Porta')
      conectar(porta, inbox)
      conectar(porta, create(:inbox, account: account))

      desconectar(porta, inbox)

      expect(porta.events.parado_sem_onde_trabalhar).to be_empty
    end
  end

  describe 'Areas.vincular! com ativar' do
    it 'vincula e liga o agente parado na mesma operação' do
      conectar(agente('Porta'), inbox)
      parado = agente('Financeiro', status: :paused, enabled: false)

      vinculo = Autonomia::Agents::Areas.vincular!(agent: parado, inbox: inbox, ativar: true)

      expect(vinculo).to have_attributes(papel: 'area', deleted_at: nil)
      expect(parado.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'devolve à área e liga o agente que parou por ficar sem onde trabalhar' do
      conectar(agente('Porta'), inbox)
      area = agente('Financeiro')
      primeiro = Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)
      Autonomia::Agents::Areas.desvincular!(agent: area, inbox: inbox)
      expect(area.reload.operating?).to be(false)

      de_volta = Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox, ativar: true)

      expect(de_volta.id).to eq(primeiro.id)
      expect(area.reload).to have_attributes(status: 'active', enabled: true)
    end

    it 'sem ativar, segue recusando quem não atende' do
      conectar(agente('Porta'), inbox)
      parado = agente('Financeiro', status: :paused, enabled: false)

      expect { Autonomia::Agents::Areas.vincular!(agent: parado, inbox: inbox) }
        .to raise_error(Autonomia::Agents::Areas::AgenteNaoAtende)
    end

    it 'recusa o interno mesmo com ativar' do
      conectar(agente('Porta'), inbox)
      interno = agente('Ana', actuation: :internal, status: :paused, enabled: false)

      expect { Autonomia::Agents::Areas.vincular!(agent: interno, inbox: inbox, ativar: true) }
        .to raise_error(Autonomia::Agents::Areas::AgenteInterno)
    end

    it 'desfaz o vínculo quando ligar o agente falha' do
      conectar(agente('Porta'), inbox)
      parado = agente('Financeiro', status: :paused, enabled: false)
      parado.update_columns(tone: 'x' * (described_class::MAX_TONE_LENGTH + 1)) # rubocop:disable Rails/SkipsModelValidations

      expect { Autonomia::Agents::Areas.vincular!(agent: parado, inbox: inbox, ativar: true) }
        .to raise_error(ActiveRecord::RecordInvalid)
        .and(not_change(Autonomia::Agents::AgentInbox, :count))
        .and(not_change(AgentBot, :count))
      expect(parado.reload.status).to eq('paused')
    end
  end

  describe 'InboxConnector com ativar' do
    it 'desfaz vínculo, espelho e caixa do bot quando ligar o agente falha' do
      parado = agente('Livia', status: :paused, enabled: false)
      parado.update_columns(tone: 'x' * (described_class::MAX_TONE_LENGTH + 1)) # rubocop:disable Rails/SkipsModelValidations
      conector = Autonomia::Agents::Operate::InboxConnector.new(agent: parado, inbox: inbox, ativar: true)

      expect { conector.perform(connect: true) }
        .to raise_error(ActiveRecord::RecordInvalid)
        .and(not_change(Autonomia::Agents::AgentInbox, :count))
        .and(not_change(AgentBot, :count))
        .and(not_change(AgentBotInbox, :count))
      expect(parado.reload).to have_attributes(status: 'paused', enabled: false)
    end
  end
end
