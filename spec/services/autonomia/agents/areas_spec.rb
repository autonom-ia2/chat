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

    it 'recusa agente que não está atendendo (pausado ou desligado), sem deixar espelho' do
      pausado = agente('Pausado', status: :paused)

      expect { described_class.vincular!(agent: pausado, inbox: inbox) }
        .to raise_error(described_class::AgenteNaoAtende)
        .and(not_change(AgentBot, :count))
    end

    it 'recusa agente de sistema (ex.: o do Guia)' do
      de_sistema = agente('Guia', config: { 'system_key' => 'guia' })

      expect { described_class.vincular!(agent: de_sistema, inbox: inbox) }
        .to raise_error(described_class::AgenteDeSistema)
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
      # #1366: era a única caixa dele, então parou; volta com ativar, que o liga junto com o vínculo.
      expect(agente_da_area.reload.operating?).to be(false)

      expect { described_class.vincular!(agent: agente_da_area, inbox: inbox, ativar: true) }.not_to change(AgentBot, :count)
      expect(area.reload).to have_attributes(deleted_at: nil, papel: 'area')
      expect(agente_da_area.reload.operating?).to be(true)
    end

    # Só reenfileira o turno que estava EM ANDAMENTO (a marca do debounce do ReplyJob aponta para a mensagem e é
    # recente). Mensagem antiga sem turno nunca vira resposta nova: seria envio a cliente real, em lote.
    def turno_em_andamento(conversa, mensagem, at: Time.current)
      stamp = { 'pending_message_id' => mensagem.id, 'at' => at.to_f }
      conversa.update!(additional_attributes: conversa.additional_attributes.to_h.merge(
        Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => stamp
      ))
    end

    def pergunta_em(conversa, texto = 'e o boleto?')
      create(:message, account: account, conversation: conversa, message_type: :incoming, content: texto)
    end

    it 'devolve à porta e enfileira uma vez a resposta à mensagem cujo turno estava em andamento' do
      atendida = conversa(ai_assignee: area.agent_bot, status: :open)
      pergunta = pergunta_em(atendida)
      turno_em_andamento(atendida, pergunta)

      expect { described_class.desvincular!(agent: agente_da_area, inbox: inbox) }
        .to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob).with(atendida.id, pergunta.id).exactly(:once)
    end

    it 'não enfileira mensagem antiga do cliente sem turno em andamento' do
      atendida = conversa(ai_assignee: area.agent_bot, status: :open)
      pergunta_em(atendida, 'ok, obrigado')

      expect { described_class.desvincular!(agent: agente_da_area, inbox: inbox) }
        .not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
    end

    it 'não enfileira quando a marca do turno é velha, ou aponta para outra mensagem' do
      velha = conversa(ai_assignee: area.agent_bot, status: :open)
      turno_em_andamento(velha, pergunta_em(velha), at: 3.days.ago)
      outra = conversa(ai_assignee: area.agent_bot, status: :open)
      turno_em_andamento(outra, pergunta_em(outra, 'primeira'))
      pergunta_em(outra, 'segunda, que não abriu turno')

      expect { described_class.desvincular!(agent: agente_da_area, inbox: inbox) }
        .not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
    end

    it 'não enfileira resposta quando a última mensagem já foi respondida' do
      atendida = conversa(ai_assignee: area.agent_bot, status: :open)
      turno_em_andamento(atendida, pergunta_em(atendida, 'oi'))
      create(:message, account: account, conversation: atendida, message_type: :outgoing, sender: area.agent_bot, content: 'olá')

      expect { described_class.desvincular!(agent: agente_da_area, inbox: inbox) }
        .not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
    end

    it 'pausar a área com várias conversas reenfileira só as que tinham turno em andamento' do
      em_andamento = conversa(ai_assignee: area.agent_bot, status: :open)
      pergunta = pergunta_em(em_andamento)
      turno_em_andamento(em_andamento, pergunta)
      2.times { pergunta_em(conversa(ai_assignee: area.agent_bot, status: :open), 'ok, obrigado') }

      agente_da_area.update!(status: :paused)

      respostas = enqueued_jobs.select { |job| job['job_class'] == 'Autonomia::Agents::Operate::ReplyJob' }
      expect(respostas.map { |job| job['arguments'] }).to eq([[em_andamento.id, pergunta.id]])
    end

    it 'é idempotente e não toca a porta' do
      described_class.desvincular!(agent: agente_da_area, inbox: inbox)

      expect { described_class.desvincular!(agent: agente_da_area, inbox: inbox) }.not_to raise_error
      expect { described_class.desvincular!(agent: agente_da_porta, inbox: inbox) }
        .not_to(change { porta.reload.attributes })
    end
  end

  # A área só existe com porta ativa: em todo caminho que tira a porta, as áreas da caixa saem antes, e as conversas
  # delas vão direto para a equipe humana (sem passar pelo robô da porta, que está saindo).
  describe 'quando a porta sai da caixa' do
    let!(:area) { described_class.vincular!(agent: agente_da_area, inbox: inbox) }
    let!(:da_area) do
      create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(ai_assignee: area.agent_bot, status: :open) }
    end

    def areas_ativas
      Autonomia::Agents::AgentInbox.kept.area.where(inbox_id: inbox.id)
    end

    it 'pelo desconectar da porta, sem atribuir antes ao robô da porta' do
      expect(Conversations::AssignmentService).not_to receive(:new)

      Autonomia::Agents::Operate::InboxConnector.new(agent: agente_da_porta, inbox: inbox).perform(connect: false)

      expect(areas_ativas).to be_empty
      expect(da_area.reload).to have_attributes(assignee_agent_bot_id: nil, status: 'open')
    end

    it 'pela exclusão lógica do agente da porta' do
      Autonomia::Agents::SoftDelete.new(agent: agente_da_porta, actor: nil).perform

      expect(areas_ativas).to be_empty
      expect(da_area.reload).to have_attributes(assignee_agent_bot_id: nil, status: 'open')
    end

    it 'pelo destroy do agente da porta' do
      agente_da_porta.destroy!

      expect(areas_ativas).to be_empty
      expect(da_area.reload).to have_attributes(assignee_agent_bot_id: nil, status: 'open')
    end
  end
end
